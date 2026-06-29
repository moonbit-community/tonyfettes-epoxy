///|
/// Two phases, deliberately separated:
///   - `analyze` does ALL type resolution. Every lookup returns `Option`; an
///     unmapped/unsupported type propagates to a `Defer(reason)` — never a
///     fabricated default. This is the single gate that decides emit-vs-skip.
///   - `render` only builds strings from an already-validated `Plan`, so it
///     does no fallible lookups and cannot silently produce wrong code.

///|
/// A MoonBit type appearing in a generated binding. It knows how to print
/// itself and how it is represented across the C FFI boundary — so we never
/// pass these facts around as bare strings.
priv enum MType {
  U32
  I32
  F32
  F64
  I64
  U64
  Bool
  Bytes
  Array(MType) // FixedArray[elem]
}

///|
/// The MoonBit-source spelling, e.g. `UInt`, `FixedArray[Float]`.
fn MType::moonbit(self : MType) -> String {
  match self {
    U32 => "UInt"
    I32 => "Int"
    F32 => "Float"
    F64 => "Double"
    I64 => "Int64"
    U64 => "UInt64"
    Bool => "Bool"
    Bytes => "Bytes"
    Array(e) => "FixedArray[\{e.moonbit()}]"
  }
}

///|
/// The C type this arrives as on the shim side (MoonBit ABI).
fn MType::c_abi(self : MType) -> String {
  match self {
    U32 => "uint32_t"
    I32 => "int32_t"
    F32 => "float"
    F64 => "double"
    I64 => "int64_t"
    U64 => "uint64_t"
    Bool => "int32_t"
    Bytes => "moonbit_bytes_t"
    Array(e) => "\{e.c_abi()}*"
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
/// Everything `render` needs, fully resolved — no further fallible lookups.
priv struct Plan {
  params : Array[Binding]
  ret : Ret
}

///|
/// How one parameter crosses the FFI boundary: its MoonBit representation
/// (`mty`, which yields both the source type and the ABI type) plus the
/// faithful GL type to cast to in the call (`gl`).
priv struct Binding {
  name : String
  mty : MType
  gl : CType
}

///|
/// The shape of a command's return value.
priv enum Ret {
  Void
  Str
  Scalar(MType, CType)
}

// --- type resolution: all Option, no fabricated defaults -----------------

///|
/// The MoonBit type for a scalar / ptr-sized GL typedef, or None otherwise.
fn scalar_mtype(gltype : String) -> MType? {
  guard @gen.lookup(gltype) is Some(m) else { return None }
  match m.category {
    @gen.Scalar | @gen.PtrSized =>
      match m.moonbit_type {
        "UInt" => Some(U32)
        "Int" => Some(I32)
        "Float" => Some(F32)
        "Double" => Some(F64)
        "Int64" => Some(I64)
        "UInt64" => Some(U64)
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
    "GLfloat" | "GLclampf" => Some(Array(F32))
    "GLdouble" | "GLclampd" => Some(Array(F64))
    "GLint" | "GLsizei" | "GLfixed" | "GLclampx" => Some(Array(I32))
    "GLuint" | "GLbitfield" | "GLenum" => Some(Array(U32))
    "GLint64" | "GLint64EXT" => Some(Array(I64))
    "GLuint64" | "GLuint64EXT" => Some(Array(U64))
    _ => None
  }
}

///|
/// The underlying C type of a GL typedef, or None if it isn't in the table.
fn c_gl_type(gltype : String) -> String? {
  guard @gen.lookup(gltype) is Some(m) else { return None }
  Some(m.c_type)
}

///|
/// Reconstruct the faithful C type for a function-pointer cast, recursing
/// through pointer levels (e.g. `const float *`, `void *`). None if any leaf
/// typedef is unmapped.
fn CType::to_c(self : CType) -> String? {
  match self {
    Base("void") => Some("void")
    Base(name) => c_gl_type(name)
    Ptr(inner, is_const~) => {
      guard inner.to_c() is Some(inner_c) else { return None }
      Some((if is_const { "const " } else { "" }) + inner_c + " *")
    }
  }
}

///|
/// Is this a string-ish pointer return (const GLubyte* / GLchar*)?
fn is_string_ret(c : Command) -> Bool {
  c.ret.is_pointer() &&
  (c.ret.base_name() == "GLubyte" ||
    c.ret.base_name() == "GLchar" ||
    c.ret.base_name() == "GLbyte")
}

///|
/// Resolve a parameter into its FFI binding, or None if its type is unsupported.
fn param_binding(name : String, ty : CType) -> Binding? {
  let mty = match ty {
    Base(_) => scalar_mtype(ty.base_name())
    Ptr(Base(_), ..) => ptr_mtype(ty.base_name())
    _ => None // pointer-to-pointer and deeper: unsupported
  }
  guard mty is Some(mty) else { return None }
  // ensure the cast is renderable too (part of the gate)
  guard ty.to_c() is Some(_) else { return None }
  Some({ name, mty, gl: ty })
}

///|
/// Build the emit plan for a command, resolving every type. None if the
/// command can't be emitted (unsupported pointer/callback/unmapped type) — it
/// is simply skipped; no wrong code is ever produced.
fn plan(c : Command) -> Plan? {
  let ret = if c.ret.is_void() {
    Void
  } else if is_string_ret(c) {
    Str
  } else if c.ret.is_pointer() {
    return None // non-string pointer return: unsupported
  } else {
    guard scalar_mtype(c.ret.base_name()) is Some(mty) else { return None }
    guard c.ret.to_c() is Some(_) else { return None }
    Scalar(mty, c.ret)
  }
  let params = []
  for p in c.params {
    if p.ty.base_name().has_prefix("GLDEBUGPROC") ||
      p.ty.base_name().has_prefix("GLVULKAN") {
      return None // callback param: unsupported
    }
    guard param_binding(safe_ident(p.name), p.ty) is Some(b) else {
      return None
    }
    params.push(b)
  }
  Some({ params, ret })
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
fn safe_ident(name : String) -> String {
  match name {
    "type" | "in" | "fn" | "let" | "mut" | "if" | "else" | "match" | "while"
    | "for" | "return" | "break" | "continue" | "loop" | "guard" | "ref" | "as"
    | "is" | "and" | "or" | "not" | "test" | "trait" | "impl" | "enum"
    | "struct" | "pub" | "priv" => name + "_"
    _ => name
  }
}

// --- rendering: pure string building from a validated Plan ---------------

///|
/// The two generated artifacts for one command.
priv struct Rendered {
  moonbit : String
  c : String
}

///|
/// The GL cast type for a binding. analyze already proved this is `Some`, so a
/// `None` here would be a generator bug — we surface it loudly, not silently.
fn Binding::cast(self : Binding) -> String {
  match self.gl.to_c() {
    Some(s) => s
    None => abort("generator bug: unmapped type reached render: \{self.name}")
  }
}

///|
/// Generate the MoonBit binding + C call shim for a command.
fn render(c : Command, plan : Plan) -> Rendered {
  let mbt = StringBuilder::new()
  let cc = StringBuilder::new()
  let fn_name = snake(c.name)
  let sym = "epoxy_" + c.name
  let slot = "d_" + c.name
  let names = plan.params.map(fn(b) { b.name })
  let mbt_params = plan.params.map(fn(b) { b.name + " : " + b.mty.moonbit() })
  let c_shim_params = plan.params.map(fn(b) { b.mty.c_abi() + " " + b.name })
  let gl_sig = plan.params.map(fn(b) { b.cast() })
  let gl_cast_args = plan.params.map(fn(b) { "(" + b.cast() + ")" + b.name })
  let sig_str = if gl_sig.is_empty() { "void" } else { gl_sig.join(", ") }
  let borrowed = []
  for b in plan.params {
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
  let (ret_mbt, ext_ret) = match plan.ret {
    Void => ("Unit", "Unit")
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
  match plan.ret {
    Str => mbt.write_string("  decode_utf8(\{call})\n")
    _ => mbt.write_string("  \{call}\n")
  }
  mbt.write_string("}\n\n")

  // --- C shim -----------------------------------------------------------
  let c_params = ["void *fp", ..c_shim_params]
  let cargs = gl_cast_args.join(", ")
  match plan.ret {
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
    Void => {
      cc.write_string("void \{sym}(\{c_params.join(", ")}) {\n")
      cc.write_string("  ((void(*)(\{sig_str}))fp)(\{cargs});\n}\n\n")
    }
    Scalar(mty, gl) => {
      let abi = mty.c_abi()
      let ret_gl = match gl.to_c() {
        Some(s) => s
        None => abort("generator bug: unmapped return type: \{c.name}")
      }
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
