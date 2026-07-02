///|
/// Two phases, deliberately separated:
///   - `Command::signature` does ALL type resolution against the `@gen` type
///     table. Every lookup returns `Option`; an unmapped/unsupported type makes
///     the whole signature `None` (the command is skipped) — never a default.
///   - `render` builds strings from an already-resolved `Signature`. Every type
///     is a concrete `@gen.CType`/`@gen.MType`, so rendering is total.

///|
/// One parameter, fully resolved: its MoonBit representation (`mty`), which
/// yields both the public source type and the `FuncRef` ABI spelling.
priv struct Binding {
  name : String
  mty : @gen.MType
}

///|
/// Resolve a parameter into its binding, or None if its type is unsupported.
fn Binding::new(name : String, ty : @cdecl.Declarator) -> Binding? {
  let mty = match ty {
    Base(typedef) => @gen.lookup(typedef).map(fn(info) { info.m_type })
    Ptr(inner, ..) =>
      match resolve_ctype(inner) {
        Some(elem) => pointer_mtype(elem)
        None => None
      }
  }
  guard mty is Some(mty) else { return None }
  Some({ name, mty })
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
/// shape. This is exactly the information `render` maps onto the MoonBit
/// `FuncRef` wrapper.
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
/// Resolve a parsed declarator into its concrete C type (the ABI tag used to
/// narrow returns and classify pointees), or None if a leaf typedef isn't in
/// the table.
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
/// The generated artifact for one command: its MoonBit dispatch wrapper. There
/// is no longer a per-command C shim — the resolved entry point is called
/// directly through a `FuncRef` whose type lowers to the exact GL ABI.
priv struct Rendered {
  moonbit : String
}

///|
/// Generate the MoonBit dispatch wrapper for a command. `aliases` are the
/// command's fallback entry-point names (its alias group, minus itself); when
/// non-empty the dispatch slot is built to try them in turn after the primary.
///
/// The body resolves the slot once, reinterprets the address as a `FuncRef`
/// typed to the GL function's exact ABI, marshals pointer/array params through
/// `@c.borrow_*` (a `FixedArray`/`Bytes` is a MoonBit object, so only its
/// borrowed data pointer is `T *`), calls it, and narrows any sub-word return.
fn render(c : Command, sig : Signature, aliases : Array[String]) -> Rendered {
  let mbt = StringBuilder::new()
  let fn_name = snake(c.name)
  let slot = "d_" + c.name
  let mbt_params = sig.params.map(fn(b) { b.name + " : " + b.mty.moonbit() })

  // FuncRef signature: each param and the return lowered to its exact-ABI
  // spelling. Empty param lists render as `()`.
  let fr_params = sig.params.map(fn(b) { b.mty.funcref_type() })
  let fr_param_list = if fr_params.is_empty() {
    "()"
  } else {
    "(" + fr_params.join(", ") + ")"
  }
  let (ret_mbt, fr_ret) = match sig.ret {
    Ret::Void => ("Unit", "Unit")
    Str => ("String", "@c.Pointer[Byte]")
    Scalar(mty, cast) => (mty.moonbit(), @gen.funcref_ret_type(cast, mty))
  }

  // Call arguments: a pointer param passes its borrowed pointer var (`<name>_p`),
  // every other param passes its value directly.
  let call_args = sig.params.map(fn(b) {
    if b.mty.is_pointer() {
      b.name + "_p"
    } else {
      b.name
    }
  })
  let raw_call = "fp(\{call_args.join(", ")})"

  // Recover the public return value from the raw FuncRef result.
  let result_expr = match sig.ret {
    Ret::Void => raw_call
    Str => "@utf8.decode_lossy(epoxy_cstr(\{raw_call})[:])"
    Scalar(mty, cast) =>
      match @gen.narrow_of(cast, mty) {
        None => raw_call
        MaskU8 => "(\{raw_call}) & 0xFF"
        SignU8 => "((\{raw_call}) << 24) >> 24"
        MaskU16 => "(\{raw_call}) & 0xFFFF"
        SignU16 => "((\{raw_call}) << 16) >> 16"
        BoolU8 => "((\{raw_call}) & 0xFF) != 0"
      }
  }

  // Nest a borrow closure per pointer param, innermost being the call result, so
  // every backing buffer stays live across the call.
  let pointer_params = sig.params.filter(fn(b) { b.mty.is_pointer() })
  let mut body = result_expr
  for i = pointer_params.length() - 1; i >= 0; i = i - 1 {
    let b = pointer_params[i]
    let borrow = if b.mty is Bytes {
      "@c.borrow_bytes"
    } else {
      "@c.borrow_array"
    }
    body = "\{borrow}(\{b.name}, fn(\{b.name}_p) { \{body} })"
  }

  // --- emit -------------------------------------------------------------
  let slot_decl = if aliases.is_empty() {
    "let \{slot} : Dispatch = Dispatch::new(\"\{c.name}\")\n\n"
  } else {
    let quoted = aliases.map(fn(a) { "\"\{a}\"" }).join(", ")
    "let \{slot} : Dispatch = Dispatch::with_aliases(\"\{c.name}\", [\{quoted}])\n\n"
  }
  mbt.write_string("///|\n")
  mbt.write_string(slot_decl)
  mbt.write_string("///|\n")
  mbt.write_string(
    "pub fn \{fn_name}(\{mbt_params.join(", ")}) -> \{ret_mbt} {\n",
  )
  mbt.write_string(
    "  let fp : FuncRef[\{fr_param_list} -> \{fr_ret}] = \{slot}.get().unsafe_into()\n",
  )
  mbt.write_string("  \{body}\n")
  mbt.write_string("}\n\n")
  { moonbit: mbt.to_string() }
}
