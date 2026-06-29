///|
/// Two phases, deliberately separated:
///   - `Command::signature` does ALL type resolution against the `@gen` type
///     table. Every lookup returns `Option`; an unmapped/unsupported type makes
///     the whole signature `None` (the command is skipped) — never a default.
///   - `render` builds strings from an already-resolved `Signature`. Every type
///     is a concrete `@gen.CType`/`@gen.MType`, so rendering is total.

///|
/// One parameter, fully resolved: its MoonBit representation (`mty`, which
/// yields both the source type and the ABI type) and the faithful C type to
/// cast to in the call (`cast`).
priv struct Binding {
  name : String
  mty : @gen.MType
  cast : @gen.CType
}

///|
/// Resolve a parameter into its binding, or None if its type is unsupported.
fn Binding::new(name : String, ty : @cdecl.Declarator) -> Binding? {
  guard resolve_ctype(ty) is Some(cast) else { return None }
  let mty = match ty {
    Base(typedef) => @gen.lookup(typedef).map(fn(info) { info.m_type })
    Ptr(inner, ..) =>
      match resolve_ctype(inner) {
        Some(elem) => pointer_mtype(elem)
        None => None
      }
  }
  guard mty is Some(mty) else { return None }
  Some({ name, mty, cast })
}

///|
/// The shape of a command's return value.
priv enum Ret {
  Void
  Str
  Scalar(@gen.MType, @gen.CType)
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
      guard @gen.lookup(name) is Some(info) else { return None }
      guard resolve_ctype(self.ret) is Some(cast) else { return None }
      Scalar(info.m_type, cast)
    }
  }
  let params = []
  for p in self.params {
    if p.ty.base_name().has_prefix("GLDEBUGPROC") ||
      p.ty.base_name().has_prefix("GLVULKAN") {
      return None // callback param: unsupported
    }
    guard Binding::new(moonbit_safe_ident(p.name), p.ty) is Some(b) else {
      return None
    }
    params.push(b)
  }
  Some({ params, ret })
}

// --- type resolution: declarator -> concrete types via the @gen table ----

///|
/// Resolve a parsed declarator into its concrete C type (for the cast), or None
/// if a leaf typedef isn't in the table.
fn resolve_ctype(ty : @cdecl.Declarator) -> @gen.CType? {
  match ty {
    Base("void" | "GLvoid") => Some(Void)
    Base(name) => @gen.lookup(name).map(fn(info) { info.c_type })
    Ptr(inner, is_const~) =>
      match resolve_ctype(inner) {
        Some(ic) => Some(Pointer(ic, is_const~))
        None => None
      }
  }
}

///|
/// The MoonBit type for a single pointer to an element of the given C type:
/// byte-sized elements become raw `Bytes`, wider scalars a `FixedArray`, and a
/// pointer-to-char-pointer (the `const GLchar *const *` of `glShaderSource` &c.)
/// becomes a `FixedArray[Bytes]` — whose in-memory layout (a run of pointers to
/// each byte buffer) already *is* the `char **` GL expects, so no marshalling is
/// needed. Anything without a native fixed-width array (16-bit, pointer-sized)
/// is unsupported.
fn pointer_mtype(elem : @gen.CType) -> @gen.MType? {
  match elem {
    Void | Char | Byte | SByte => Some(Bytes)
    UInt => Some(Array(UInt))
    Int => Some(Array(Int))
    Float => Some(Array(Float))
    Double => Some(Array(Double))
    Int64 => Some(Array(Int64))
    UInt64 => Some(Array(UInt64))
    // 16-bit element arrays: FixedArray[Int16]/[UInt16] are packed int16_t*/
    // uint16_t*, matching `const GLshort *` &c. GLhalf rides UShort here — no
    // native f16, so its bits pass through verbatim.
    Short => Some(Array(Int16))
    UShort => Some(Array(UInt16))
    // an array of C strings: pointer-to-(pointer-to-char). Restricted to
    // char-like pointees — `void **`/`T **` of other element types denote
    // out-pointers we can't faithfully represent and stay skipped.
    Pointer(Char | Byte | SByte, ..) => Some(Array(Bytes))
    _ => None
  }
}

///|
/// Render one GL enum as a MoonBit constant, typed by its `EnumKind`. The value
/// is emitted verbatim from the registry (hex/decimal/negative); the explicit
/// type annotation makes a `0xFFFFFFFF` carry as `UInt` rather than overflow.
fn render_enum(e : EnumDef) -> String {
  let ty = match e.kind {
    Unsigned => "UInt"
    Unsigned64 => "UInt64"
    Signed => "Int"
  }
  "///|\npub const \{e.name} : \{ty} = \{e.value}\n\n"
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
        name[i + 1].to_int() >= 'a' &&
        name[i + 1].to_int() <= 'z'
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
    "type"
    | "in"
    | "fn"
    | "let"
    | "mut"
    | "if"
    | "else"
    | "match"
    | "while"
    | "for"
    | "return"
    | "break"
    | "continue"
    | "loop"
    | "guard"
    | "ref"
    | "as"
    | "is"
    | "and"
    | "or"
    | "not"
    | "test"
    | "trait"
    | "impl"
    | "enum"
    | "struct"
    | "pub"
    | "priv" => name + "_"
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
/// Generate the MoonBit binding + C call shim for a command. `aliases` are the
/// command's fallback entry-point names (its alias group, minus itself); when
/// non-empty the dispatch slot is built to try them in turn after the primary.
fn render(c : Command, sig : Signature, aliases : Array[String]) -> Rendered {
  let mbt = StringBuilder::new()
  let cc = StringBuilder::new()
  let fn_name = snake(c.name)
  let sym = "epoxy_" + c.name
  let slot = "d_" + c.name
  let names = sig.params.map(fn(b) { b.name })
  let mbt_params = sig.params.map(fn(b) { b.name + " : " + b.mty.moonbit() })
  let c_shim_params = sig.params.map(fn(b) { b.mty.c_abi() + " " + b.name })
  let gl_sig = sig.params.map(fn(b) { b.cast.c() })
  let gl_cast_args = sig.params.map(fn(b) { "(" + b.cast.c() + ")" + b.name })
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
  let slot_decl = if aliases.is_empty() {
    "let \{slot} : Dispatch = Dispatch::new(\"\{c.name}\")\n\n"
  } else {
    let quoted = aliases.map(fn(a) { "\"\{a}\"" }).join(", ")
    "let \{slot} : Dispatch = Dispatch::with_aliases(\"\{c.name}\", [\{quoted}])\n\n"
  }
  mbt.write_string("///|\n")
  mbt.write_string(slot_decl)
  mbt.write_string("///|\n")
  let ffi_params = ["fp : CPtr", ..mbt_params]
  mbt.write_string(
    "\{borrow_line}extern \"c\" fn \{sym}(\{ffi_params.join(", ")}) -> \{ext_ret} = \"\{sym}\"\n\n",
  )
  mbt.write_string("///|\n")
  mbt.write_string(
    "pub fn \{fn_name}(\{mbt_params.join(", ")}) -> \{ret_mbt} {\n",
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
      cc.write_string(
        "  const unsigned char *(*f)(\{sig_str}) = (const unsigned char *(*)(\{sig_str}))fp;\n",
      )
      cc.write_string("  const unsigned char *s = f(\{cargs});\n")
      cc.write_string("  if (!s) return moonbit_make_bytes(0, 0);\n")
      cc.write_string("  size_t len = strlen((const char *)s);\n")
      cc.write_string(
        "  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);\n",
      )
      cc.write_string("  memcpy(out, s, len);\n")
      cc.write_string("  return out;\n}\n\n")
    }
    Ret::Void => {
      cc.write_string("void \{sym}(\{c_params.join(", ")}) {\n")
      cc.write_string("  ((void(*)(\{sig_str}))fp)(\{cargs});\n}\n\n")
    }
    Scalar(mty, cast) => {
      let abi = mty.c_abi()
      let ret_gl = cast.c()
      cc.write_string("\{abi} \{sym}(\{c_params.join(", ")}) {\n")
      if mty is Bool {
        cc.write_string(
          "  return (\{abi})(((\{ret_gl}(*)(\{sig_str}))fp)(\{cargs}) != 0);\n}\n\n",
        )
      } else {
        cc.write_string(
          "  return (\{abi})((\{ret_gl}(*)(\{sig_str}))fp)(\{cargs});\n}\n\n",
        )
      }
    }
  }
  { moonbit: mbt.to_string(), c: cc.to_string() }
}
