///|
/// Classification + code generation. Given the parsed `Command`s, decide which
/// can be emitted by the first-pass generator (scalar/void/string-return only)
/// and produce the MoonBit bindings + C call shims for them.

///|
/// Why a command is (in)eligible for the first-pass generator.
priv enum Eligibility {
  Ok
  PointerParam // an argument is a pointer/array — deferred
  PointerReturn // returns a non-string pointer — deferred
  UnknownType // a type isn't in the mapping table — deferred
  Callback // a callback param — deferred
}

///|
/// MoonBit FFI type for a scalar/ptr-sized GL type, or None if not such.
fn mbt_scalar_type(gltype : String) -> String? {
  match @gen.lookup(gltype) {
    Some(m) =>
      match m.category {
        @gen.Scalar | @gen.PtrSized => Some(m.moonbit_type)
        _ => None
      }
    None => None
  }
}

///|
/// The C type matching MoonBit's FFI ABI for a given MoonBit type.
fn c_abi_type(mbt : String) -> String {
  match mbt {
    "UInt" => "uint32_t"
    "Int" => "int32_t"
    "Float" => "float"
    "Double" => "double"
    "Int64" => "int64_t"
    "Bool" => "int32_t"
    _ => "int32_t"
  }
}

///|
/// The underlying C type of a GL typedef, used to cast the resolved pointer to
/// the real function signature (ABI-exact, no GL headers needed).
fn c_gl_type(gltype : String) -> String {
  match @gen.lookup(gltype) {
    Some(m) => m.c_type
    None => "int"
  }
}

///|
/// Reconstruct the faithful C type string for a function-pointer cast,
/// recursing through pointer levels (e.g. `const float *`, `void *`).
fn CType::to_c(self : CType) -> String {
  match self {
    Base("void") => "void"
    Base(name) => c_gl_type(name)
    Ptr(inner, is_const~) =>
      (if is_const { "const " } else { "" }) + inner.to_c() + " *"
  }
}

///|
/// How a single pointer param is represented: the MoonBit container type and
/// the matching C shim parameter type (the MoonBit-ABI pointer it arrives as).
/// `None` for element types with no native fixed-width array (16-bit shorts,
/// opaque handles, ...) — those stay deferred.
fn ptr_element(base : String) -> (String, String)? {
  match base {
    // byte-addressable data / strings / opaque pixel buffers -> raw Bytes
    "void" | "GLvoid" | "GLchar" | "GLcharARB" | "GLubyte" | "GLbyte" | "GLboolean" =>
      Some(("Bytes", "moonbit_bytes_t"))
    "GLfloat" | "GLclampf" => Some(("FixedArray[Float]", "float*"))
    "GLdouble" | "GLclampd" => Some(("FixedArray[Double]", "double*"))
    "GLint" | "GLsizei" | "GLfixed" | "GLclampx" =>
      Some(("FixedArray[Int]", "int32_t*"))
    "GLuint" | "GLbitfield" | "GLenum" => Some(("FixedArray[UInt]", "uint32_t*"))
    "GLint64" | "GLint64EXT" => Some(("FixedArray[Int64]", "int64_t*"))
    "GLuint64" | "GLuint64EXT" => Some(("FixedArray[UInt64]", "uint64_t*"))
    _ => None
  }
}

///|
/// How one parameter crosses the FFI boundary.
priv struct Binding {
  mbt : String // MoonBit parameter type
  c_abi : String // C shim parameter type (MoonBit ABI)
  cast : String // GL type to cast to in the call (faithful C type)
  borrow : Bool // pointer params must be #borrow'd
}

///|
/// Compute the binding for a parameter type, or None if unsupported (deferred).
fn ty_binding(ty : CType) -> Binding? {
  match ty {
    // by-value scalar / ptr-sized integer
    Base(_) =>
      match mbt_scalar_type(ty.base_name()) {
        Some(mbt) =>
          Some({ mbt, c_abi: c_abi_type(mbt), cast: ty.to_c(), borrow: false })
        None => None
      }
    // single pointer to a base type -> array / bytes passthrough
    Ptr(Base(_), ..) =>
      match ptr_element(ty.base_name()) {
        Some((mbt, c_abi)) => Some({ mbt, c_abi, cast: ty.to_c(), borrow: true })
        None => None
      }
    // pointer-to-pointer and deeper: deferred
    _ => None
  }
}

///|
/// Is this a string-ish pointer return (const GLubyte* / GLchar*)?
fn is_string_ret(c : Command) -> Bool {
  c.ret.is_pointer() &&
  (c.ret.base_name() == "GLubyte" || c.ret.base_name() == "GLchar" || c.ret.base_name() == "GLbyte")
}

///|
fn classify(c : Command) -> Eligibility {
  // return type
  if c.ret.is_pointer() && !is_string_ret(c) {
    return PointerReturn
  }
  if !c.ret.is_void() && !c.ret.is_pointer() {
    if mbt_scalar_type(c.ret.base_name()) is None {
      return UnknownType
    }
  }
  // params
  for p in c.params {
    if p.ty.base_name().has_prefix("GLDEBUGPROC") ||
      p.ty.base_name().has_prefix("GLVULKAN") {
      return Callback
    }
    if ty_binding(p.ty) is None {
      // unsupported: a deferred pointer shape, or an unmapped scalar type
      return if p.ty.is_pointer() { PointerParam } else { UnknownType }
    }
  }
  Ok
}

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
///|
/// MoonBit reserved words that can appear as GL parameter names; suffix with
/// '_' so the generated code parses.
fn safe_ident(name : String) -> String {
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

///|
/// Generated code for one command, as (moonbit, c) string fragments.
fn emit(c : Command) -> (String, String) {
  let mbt = StringBuilder::new()
  let cc = StringBuilder::new()
  let fn_name = snake(c.name)
  let shim = "epoxy_" + c.name
  let slot = "d_" + c.name

  // --- per-parameter bindings (scalar by-value or pointer passthrough) --
  let bindings = c.params.map(fn(p) { ty_binding(p.ty).unwrap() })
  let names = c.params.map(fn(p) { safe_ident(p.name) })
  let mbt_params = names.mapi(fn(i, n) { n + " : " + bindings[i].mbt })
  let call_args = names
  let c_shim_params = names.mapi(fn(i, n) { bindings[i].c_abi + " " + n })
  let gl_sig = bindings.map(fn(b) { b.cast })
  let gl_cast_args = names.mapi(fn(i, n) { "(" + bindings[i].cast + ")" + n })
  let sig_str = if gl_sig.is_empty() { "void" } else { gl_sig.join(", ") }

  // pointer params must be borrowed (C must not retain them past the call)
  let borrowed = []
  for i, n in names {
    if bindings[i].borrow {
      borrowed.push(n)
    }
  }
  let borrow_line = if borrowed.is_empty() {
    ""
  } else {
    "#borrow(\{borrowed.join(", ")})\n"
  }

  // --- MoonBit side -----------------------------------------------------
  mbt.write_string("///|\n")
  mbt.write_string("let \{slot} : Dispatch = Dispatch::new(\"\{c.name}\")\n\n")
  mbt.write_string("///|\n")
  let ffi_params = ["fp : CPtr", ..mbt_params]
  if is_string_ret(c) {
    mbt.write_string("\{borrow_line}extern \"c\" fn epoxy_\{c.name}(\{ffi_params.join(", ")}) -> Bytes = \"\{shim}\"\n\n")
    mbt.write_string("///|\n")
    mbt.write_string("pub fn \{fn_name}(\{mbt_params.join(", ")}) -> String raise ResolveError {\n")
    let args = [slot + ".get()", ..call_args]
    mbt.write_string("  decode_utf8(epoxy_\{c.name}(\{args.join(", ")}))\n")
    mbt.write_string("}\n\n")
  } else if c.ret.is_void() {
    mbt.write_string("\{borrow_line}extern \"c\" fn epoxy_\{c.name}(\{ffi_params.join(", ")}) -> Unit = \"\{shim}\"\n\n")
    mbt.write_string("///|\n")
    mbt.write_string("pub fn \{fn_name}(\{mbt_params.join(", ")}) -> Unit raise ResolveError {\n")
    let args = [slot + ".get()", ..call_args]
    mbt.write_string("  epoxy_\{c.name}(\{args.join(", ")})\n")
    mbt.write_string("}\n\n")
  } else {
    let ret_mbt = mbt_scalar_type(c.ret.base_name()).unwrap()
    mbt.write_string("\{borrow_line}extern \"c\" fn epoxy_\{c.name}(\{ffi_params.join(", ")}) -> \{ret_mbt} = \"\{shim}\"\n\n")
    mbt.write_string("///|\n")
    mbt.write_string("pub fn \{fn_name}(\{mbt_params.join(", ")}) -> \{ret_mbt} raise ResolveError {\n")
    let args = [slot + ".get()", ..call_args]
    mbt.write_string("  epoxy_\{c.name}(\{args.join(", ")})\n")
    mbt.write_string("}\n\n")
  }

  // --- C shim -----------------------------------------------------------
  let c_params = ["void *fp", ..c_shim_params]
  let cargs = gl_cast_args.join(", ")
  if is_string_ret(c) {
    cc.write_string("moonbit_bytes_t \{shim}(\{c_params.join(", ")}) {\n")
    cc.write_string("  const unsigned char *(*f)(\{sig_str}) = (const unsigned char *(*)(\{sig_str}))fp;\n")
    cc.write_string("  const unsigned char *s = f(\{cargs});\n")
    cc.write_string("  if (!s) return moonbit_make_bytes(0, 0);\n")
    cc.write_string("  size_t len = strlen((const char *)s);\n")
    cc.write_string("  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);\n")
    cc.write_string("  memcpy(out, s, len);\n")
    cc.write_string("  return out;\n}\n\n")
  } else if c.ret.is_void() {
    cc.write_string("void \{shim}(\{c_params.join(", ")}) {\n")
    cc.write_string("  ((void(*)(\{sig_str}))fp)(\{cargs});\n}\n\n")
  } else {
    let ret_mbt = mbt_scalar_type(c.ret.base_name()).unwrap()
    let ret_abi = c_abi_type(ret_mbt)
    let ret_gl = c.ret.to_c()
    cc.write_string("\{ret_abi} \{shim}(\{c_params.join(", ")}) {\n")
    if ret_mbt == "Bool" {
      cc.write_string("  return (\{ret_abi})(((\{ret_gl}(*)(\{sig_str}))fp)(\{cargs}) != 0);\n}\n\n")
    } else {
      cc.write_string("  return (\{ret_abi})((\{ret_gl}(*)(\{sig_str}))fp)(\{cargs});\n}\n\n")
    }
  }
  (mbt.to_string(), cc.to_string())
}
