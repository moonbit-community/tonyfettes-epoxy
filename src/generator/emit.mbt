///|
/// Two phases, deliberately separated:
///   - `Command::signature` does ALL type resolution. Every lookup returns
///     `Option`; an unmapped/unsupported type makes the whole signature `None`
///     (the command is skipped) — never a fabricated default.
///   - `render` builds strings from an already-resolved `Signature`. Every type
///     is concrete by then, so rendering is total and cannot miscompile.

///|
/// A MoonBit type appearing in a generated binding. It knows how to print
/// itself and how it is represented across the C FFI boundary.
priv enum MType {
  UInt
  Int
  Float
  Double
  Int64
  UInt64
  Bool
  Bytes
  Array(MType) // FixedArray[elem]
}

///|
/// The MoonBit-source spelling, e.g. `UInt`, `FixedArray[Float]`.
fn MType::moonbit(self : MType) -> String {
  match self {
    UInt => "UInt"
    Int => "Int"
    Float => "Float"
    Double => "Double"
    Int64 => "Int64"
    UInt64 => "UInt64"
    Bool => "Bool"
    Bytes => "Bytes"
    Array(e) => "FixedArray[\{e.moonbit()}]"
  }
}

///|
/// The C type this value arrives as on the shim side (the MoonBit ABI).
fn MType::c_abi(self : MType) -> ResolvedCType {
  match self {
    UInt => Prim("uint32_t")
    Int => Prim("int32_t")
    Float => Prim("float")
    Double => Prim("double")
    Int64 => Prim("int64_t")
    UInt64 => Prim("uint64_t")
    Bool => Prim("int32_t")
    Bytes => Prim("moonbit_bytes_t")
    Array(e) => Pointer(e.c_abi(), is_const=false)
  }
}

///|
/// Pointer-like types must be `#borrow`'d into the extern.
fn MType::is_pointer(self : MType) -> Bool {
  match self {
    Bytes | Array(_) => true
    _ => false
  }
}

///|
/// A concrete C type, with literal leaves (`unsigned int`, `moonbit_bytes_t`,
/// ...). Unlike the registry-level `CType`, every leaf is already resolved, so
/// `render` is a total, lookup-free function.
priv enum ResolvedCType {
  Void
  Prim(String)
  Pointer(ResolvedCType, is_const~ : Bool)
}

///|
fn ResolvedCType::render(self : ResolvedCType) -> String {
  match self {
    Void => "void"
    Prim(s) => s
    Pointer(inner, is_const~) =>
      (if is_const { "const " } else { "" }) + inner.render() + " *"
  }
}

///|
/// One parameter, fully resolved: its MoonBit representation (`mty`, yielding
/// both the source type and the ABI type) and the faithful GL type to cast to
/// in the call (`cast`).
priv struct Binding {
  name : String
  mty : MType
  cast : ResolvedCType
}

///|
/// Resolve a parameter into its binding, or None if its type is unsupported.
fn Binding::new(name : String, ty : @cdecl.CType) -> Binding? {
  let mty = match ty {
    Base(_) => scalar_mtype(ty.base_name())
    Ptr(Base(_), ..) => ptr_mtype(ty.base_name())
    _ => None // pointer-to-pointer and deeper: unsupported
  }
  guard mty is Some(mty) else { return None }
  guard resolve_ctype(ty) is Some(cast) else { return None }
  Some({ name, mty, cast })
}

///|
/// The shape of a command's return value.
priv enum Ret {
  Void
  Str
  Scalar(MType, ResolvedCType)
}

///|
/// A command's resolved cross-FFI signature: its parameter bindings and return
/// shape. This is exactly the information `render` maps onto both the MoonBit
/// wrapper and the C shim.
priv struct Signature {
  params : Array[Binding]
  ret : Ret
}

///|
/// Resolve a command into the signature to emit, or None if it can't be
/// expressed (unsupported pointer/callback/unmapped type) — then it is skipped,
/// never miscompiled.
fn Command::signature(self : Command) -> Signature? {
  let ret = match self.ret {
    Base("void") => Ret::Void
    Ptr(Base("GLubyte" | "GLchar" | "GLbyte"), ..) => Str
    Ptr(_, ..) => return None // non-string pointer return: unsupported
    Base(name) => {
      guard scalar_mtype(name) is Some(mty) else { return None }
      guard resolve_ctype(self.ret) is Some(cast) else { return None }
      Scalar(mty, cast)
    }
  }
  let params = []
  for p in self.params {
    if p.ty.base_name().has_prefix("GLDEBUGPROC") ||
      p.ty.base_name().has_prefix("GLVULKAN") {
      return None // callback param: unsupported
    }
    guard Binding::new(moonbit_safe_ident(p.name), p.ty) is Some(b) else { return None }
    params.push(b)
  }
  Some({ params, ret })
}

// --- type resolution: all Option, no fabricated defaults -----------------

///|
/// The MoonBit type for a scalar / ptr-sized GL typedef, or None otherwise.
fn scalar_mtype(gltype : String) -> MType? {
  guard @gen.lookup(gltype) is Some(m) else { return None }
  match m.category {
    @gen.Scalar | @gen.PtrSized =>
      match m.moonbit_type {
        "UInt" => Some(UInt)
        "Int" => Some(Int)
        "Float" => Some(Float)
        "Double" => Some(Double)
        "Int64" => Some(Int64)
        "UInt64" => Some(UInt64)
        "Bool" => Some(Bool)
        _ => None
      }
    _ => None
  }
}

///|
/// The MoonBit type for a single pointer whose element is `base`, or None for
/// elements with no native fixed-width array (16-bit, opaque handles, ...).
fn ptr_mtype(base : String) -> MType? {
  match base {
    "void" | "GLvoid" | "GLchar" | "GLcharARB" | "GLubyte" | "GLbyte"
    | "GLboolean" => Some(Bytes)
    "GLfloat" | "GLclampf" => Some(Array(Float))
    "GLdouble" | "GLclampd" => Some(Array(Double))
    "GLint" | "GLsizei" | "GLfixed" | "GLclampx" => Some(Array(Int))
    "GLuint" | "GLbitfield" | "GLenum" => Some(Array(UInt))
    "GLint64" | "GLint64EXT" => Some(Array(Int64))
    "GLuint64" | "GLuint64EXT" => Some(Array(UInt64))
    _ => None
  }
}

///|
/// Resolve a registry GL type into a concrete C type, or None if a leaf typedef
/// isn't in the mapping table. (A free function, not a method: `CType` belongs
/// to the `cdecl` package; this resolution is the generator's concern, since it
/// consults the type-mapping table.)
fn resolve_ctype(ty : @cdecl.CType) -> ResolvedCType? {
  match ty {
    Base("void") => Some(Void)
    Base(name) => {
      guard @gen.lookup(name) is Some(m) else { return None }
      Some(Prim(m.c_type))
    }
    Ptr(inner, is_const~) => {
      guard resolve_ctype(inner) is Some(ic) else { return None }
      Some(Pointer(ic, is_const~))
    }
  }
}

// --- name mangling -------------------------------------------------------

///|
/// camelCase GL name -> snake_case MoonBit name, keeping acronym runs together.
/// "glGetString" -> "gl_get_string", "glCheckFramebufferStatusEXT" -> "..._ext".
fn snake(name : String) -> String {
  fn is_upper(x : Int) -> Bool {
    x >= 'A' && x <= 'Z'
  }

  fn is_lower_or_digit(x : Int) -> Bool {
    (x >= 'a' && x <= 'z') || (x >= '0' && x <= '9')
  }

  let n = name.length()
  let sb = StringBuilder::new()
  for i in 0..<n {
    let c = name[i].to_int()
    if is_upper(c) {
      let prev_lower = i > 0 && is_lower_or_digit(name[i - 1].to_int())
      let next_lower = i + 1 < n &&
        (name[i + 1].to_int() >= 'a' && name[i + 1].to_int() <= 'z')
      if i > 0 && (prev_lower || next_lower) {
        sb.write_char('_')
      }
      sb.write_char((c + 32).unsafe_to_char())
    } else {
      sb.write_char(c.unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
/// MoonBit reserved words that can appear as GL parameter names; suffix with
/// '_' so the generated code parses.
fn moonbit_safe_ident(name : String) -> String {
  match name {
    "type" | "in" | "fn" | "let" | "mut" | "if" | "else" | "match" | "while"
    | "for" | "return" | "break" | "continue" | "loop" | "guard" | "ref" | "as"
    | "is" | "and" | "or" | "not" | "test" | "trait" | "impl" | "enum"
    | "struct" | "pub" | "priv" => name + "_"
    _ => name
  }
}

// --- rendering: pure string building from a resolved Signature -----------

///|
/// The two generated artifacts for one command.
priv struct Rendered {
  moonbit : String
  c : String
}

///|
/// Generate the MoonBit binding + C call shim for a command.
fn render(c : Command, sig : Signature) -> Rendered {
  let mbt = StringBuilder::new()
  let cc = StringBuilder::new()
  let fn_name = snake(c.name)
  let sym = "epoxy_" + c.name
  let slot = "d_" + c.name
  let names = sig.params.map(fn(b) { b.name })
  let mbt_params = sig.params.map(fn(b) { b.name + " : " + b.mty.moonbit() })
  let c_shim_params = sig.params.map(fn(b) {
    b.mty.c_abi().render() + " " + b.name
  })
  let gl_sig = sig.params.map(fn(b) { b.cast.render() })
  let gl_cast_args = sig.params.map(fn(b) { "(" + b.cast.render() + ")" + b.name })
  let sig_str = if gl_sig.is_empty() { "void" } else { gl_sig.join(", ") }
  let borrowed = []
  for b in sig.params {
    if b.mty.is_pointer() {
      borrowed.push(b.name)
    }
  }
  let borrow_line = if borrowed.is_empty() {
    ""
  } else {
    "#borrow(\{borrowed.join(", ")})\n"
  }

  // result types for the MoonBit signature / extern
  let (ret_mbt, ext_ret) = match sig.ret {
    Ret::Void => ("Unit", "Unit")
    Str => ("String", "Bytes")
    Scalar(mty, _) => (mty.moonbit(), mty.moonbit())
  }

  // --- MoonBit side -----------------------------------------------------
  mbt.write_string("///|\n")
  mbt.write_string("let \{slot} : Dispatch = Dispatch::new(\"\{c.name}\")\n\n")
  mbt.write_string("///|\n")
  let ffi_params = ["fp : CPtr", ..mbt_params]
  mbt.write_string(
    "\{borrow_line}extern \"c\" fn \{sym}(\{ffi_params.join(", ")}) -> \{ext_ret} = \"\{sym}\"\n\n",
  )
  mbt.write_string("///|\n")
  mbt.write_string(
    "pub fn \{fn_name}(\{mbt_params.join(", ")}) -> \{ret_mbt} raise ResolveError {\n",
  )
  let args = [slot + ".get()", ..names]
  let call = "\{sym}(\{args.join(", ")})"
  match sig.ret {
    Str => mbt.write_string("  @utf8.decode_lossy(\{call}[:])\n")
    _ => mbt.write_string("  \{call}\n")
  }
  mbt.write_string("}\n\n")

  // --- C shim -----------------------------------------------------------
  let c_params = ["void *fp", ..c_shim_params]
  let cargs = gl_cast_args.join(", ")
  match sig.ret {
    Str => {
      cc.write_string("moonbit_bytes_t \{sym}(\{c_params.join(", ")}) {\n")
      cc.write_string("  const unsigned char *(*f)(\{sig_str}) = (const unsigned char *(*)(\{sig_str}))fp;\n")
      cc.write_string("  const unsigned char *s = f(\{cargs});\n")
      cc.write_string("  if (!s) return moonbit_make_bytes(0, 0);\n")
      cc.write_string("  size_t len = strlen((const char *)s);\n")
      cc.write_string("  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);\n")
      cc.write_string("  memcpy(out, s, len);\n")
      cc.write_string("  return out;\n}\n\n")
    }
    Ret::Void => {
      cc.write_string("void \{sym}(\{c_params.join(", ")}) {\n")
      cc.write_string("  ((void(*)(\{sig_str}))fp)(\{cargs});\n}\n\n")
    }
    Scalar(mty, cast) => {
      let abi = mty.c_abi().render()
      let ret_gl = cast.render()
      cc.write_string("\{abi} \{sym}(\{c_params.join(", ")}) {\n")
      if mty is Bool {
        cc.write_string("  return (\{abi})(((\{ret_gl}(*)(\{sig_str}))fp)(\{cargs}) != 0);\n}\n\n")
      } else {
        cc.write_string("  return (\{abi})((\{ret_gl}(*)(\{sig_str}))fp)(\{cargs});\n}\n\n")
      }
    }
  }
  { moonbit: mbt.to_string(), c: cc.to_string() }
}
