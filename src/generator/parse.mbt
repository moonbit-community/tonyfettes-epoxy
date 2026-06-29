///|
/// Streaming parser that turns the Khronos registry `<command>` entries into
/// structured `Command` records. Only the command signatures are needed for
/// dispatch; everything else (enums, features, extensions) is skipped here.

///|
/// A C type as it appears in a command signature, modelled faithfully and
/// recursively: a base typedef leaf, or a pointer to another `CType`.
///
/// `Base` keeps the registry typedef name (e.g. "GLfloat", "void") and resolves
/// to its underlying C / MoonBit type via the type-mapping table — the single
/// source of truth — rather than re-enumerating every typedef here.
///
/// (`is_const` records whether the pointee is `const`, i.e. an input vs. output
/// buffer; `const` itself is a reserved word so the label can't be named that.)
priv enum CType {
  Base(String)
  Ptr(CType, is_const~ : Bool)
}

///|
fn CType::is_pointer(self : CType) -> Bool {
  self is Ptr(_, ..)
}

///|
fn CType::is_void(self : CType) -> Bool {
  self is Base("void")
}

///|
/// The innermost base typedef name (sees through pointers), e.g. the `GLubyte`
/// in `const GLubyte *`. Used for scalar/string classification.
fn CType::base_name(self : CType) -> String {
  match self {
    Base(name) => name
    Ptr(inner, ..) => inner.base_name()
  }
}

///|
priv struct Param {
  name : String
  ty : CType
}

///|
priv struct Command {
  name : String
  ret : CType
  params : Array[Param]
}

///|
priv enum Region {
  Outside
  Proto
  Param
}

///|
priv enum Sub {
  None
  Ptype
  Name
}

///|
/// Parse every `<command>` in the registry at `path`.
fn parse_commands(path : String) -> Array[Command] raise {
  let reader = @xml.Reader::from_file(path)
  let commands : Array[Command] = []
  let mut region = Region::Outside
  let mut sub = Sub::None

  // proto (return + function name) accumulators
  let mut proto_ptype = ""
  let mut proto_name = ""
  let mut proto_text = ""

  // current param accumulators
  let mut p_ptype = ""
  let mut p_name = ""
  let mut p_text = ""
  let mut params : Array[Param] = []
  fn finalize_type(ptype : String, text : String) -> CType {
    let mut stars = 0
    for c in text {
      if c == '*' {
        stars += 1
      }
    }
    let pointee_const = text.contains("const")
    let base = if ptype != "" { ptype } else { text.replace(old="*", new="") }
    // strip qualifiers/whitespace ("const", "struct", spaces)
    let cleaned = base
      .replace(old="const", new="")
      .replace(old="struct", new="")
      .trim(chars=" \t\n")
      .to_owned()
    // wrap the leaf in `stars` pointer levels; the innermost level carries the
    // pointee's const-ness (the input/output signal).
    let mut ty : CType = Base(cleaned)
    for i in 0..<stars {
      ty = Ptr(ty, is_const=i == 0 && pointee_const)
    }
    ty
  }

  while true {
    match reader.read_event() {
      @xml.Eof => break
      @xml.Start(el) =>
        match el.name {
          "command" => {
            region = Region::Outside
            proto_ptype = ""
            proto_name = ""
            proto_text = ""
            params = []
          }
          "proto" => {
            region = Region::Proto
            sub = Sub::None
          }
          "param" => {
            region = Region::Param
            sub = Sub::None
            p_ptype = ""
            p_name = ""
            p_text = ""
          }
          "ptype" => sub = Sub::Ptype
          "name" => sub = Sub::Name
          _ => ()
        }
      @xml.Text(t) =>
        match region {
          Region::Proto =>
            match sub {
              Sub::Ptype => proto_ptype = proto_ptype + t
              Sub::Name => proto_name = proto_name + t
              Sub::None => proto_text = proto_text + t
            }
          Region::Param =>
            match sub {
              Sub::Ptype => p_ptype = p_ptype + t
              Sub::Name => p_name = p_name + t
              Sub::None => p_text = p_text + t
            }
          Region::Outside => ()
        }
      @xml.End(name) =>
        match name {
          "ptype" | "name" => sub = Sub::None
          "proto" => region = Region::Outside
          "param" => {
            region = Region::Outside
            let ty = finalize_type(p_ptype, p_text)
            params.push({ name: p_name.trim(chars=" ").to_owned(), ty })
          }
          "command" =>
            commands.push({
              name: proto_name.trim(chars=" ").to_owned(),
              ret: finalize_type(proto_ptype, proto_text),
              params,
            })
          _ => ()
        }
      _ => ()
    }
  }
  commands
}
