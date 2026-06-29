///|
/// Streaming parser that turns the Khronos registry `<command>` entries into
/// structured `Command` records. Only the command signatures are needed for
/// dispatch; everything else (enums, features, extensions) is skipped here.

///|
/// A C type as it appears in a command signature, modelled faithfully and
/// recursively: a base typedef leaf, or a pointer to another `GlType`.
///
/// `Base` keeps the registry typedef name (e.g. "GLfloat", "void") and resolves
/// to its underlying C / MoonBit type via the type-mapping table — the single
/// source of truth — rather than re-enumerating every typedef here.
///
/// (`is_const` records whether the pointee is `const`, i.e. an input vs. output
/// buffer; `const` itself is a reserved word so the label can't be named that.)
priv enum GlType {
  Base(String)
  Ptr(GlType, is_const~ : Bool)
}

///|
/// The innermost base typedef name (sees through pointers), e.g. the `GLubyte`
/// in `const GLubyte *`. Used for scalar/string classification.
fn GlType::base_name(self : GlType) -> String {
  match self {
    Base(name) => name
    Ptr(inner, ..) => inner.base_name()
  }
}

///|
priv struct Param {
  name : String
  ty : GlType
}

///|
priv struct Command {
  name : String
  ret : GlType
  params : Array[Param]
}

///|
/// Which part of the current `<command>` we're parsing: its `<proto>` (return
/// type + function name), one of its `<param>` elements, or somewhere else
/// inside the command (`<glx>`, `<alias>`, ... — ignored).
priv enum Section {
  Elsewhere
  Proto
  Param
}

///|
/// Within a `<proto>`/`<param>`, which child element the current text belongs
/// to: the `<ptype>` (C base type), the `<name>` (identifier), or the
/// surrounding declarator tokens (`const`, `*`, spaces).
priv enum Field {
  Surrounding
  Ptype
  Name
}

///|
/// Accumulates the streamed pieces of one declaration — a `<proto>` or a
/// `<param>`: its `<ptype>`, its `<name>`, and the surrounding declarator text.
priv struct Decl {
  ptype : StringBuilder
  name : StringBuilder
  text : StringBuilder
}

///|
fn Decl::new() -> Decl {
  { ptype: StringBuilder::new(), name: StringBuilder::new(), text: StringBuilder::new() }
}

///|
/// Route a text event to the right buffer for the field currently open.
fn Decl::feed(self : Decl, field : Field, t : String) -> Unit {
  match field {
    Ptype => self.ptype.write_string(t)
    Name => self.name.write_string(t)
    Surrounding => self.text.write_string(t)
  }
}

///|
/// The declared identifier (function or parameter name).
fn Decl::ident(self : Decl) -> String {
  self.name.to_string().trim(chars=" ").to_owned()
}

///|
/// A token of a C declarator fragment.
priv enum Token {
  Star // *
  Const // const qualifier
  Struct // struct keyword (cl_* extension types)
  Word(String) // a type name, e.g. "void", "GLfloat"
}

///|
/// Lex a C declarator fragment: whitespace separates words, each `*` is its own
/// token, and the `const`/`struct` keywords are recognised. e.g. "const  *" ->
/// [Const, Star], "struct _cl_event" -> [Struct, Word("_cl_event")].
fn tokenize_declarator(s : String) -> Array[Token] {
  let toks : Array[Token] = []
  let mut cur = StringBuilder::new()
  fn flush() -> Unit {
    let w = cur.to_string()
    if w != "" {
      toks.push(match w {
        "const" => Const
        "struct" => Struct
        _ => Word(w)
      })
    }
    cur = StringBuilder::new()
  }

  for c in s {
    if c == '*' {
      flush()
      toks.push(Star)
    } else if c == ' ' || c == '\t' || c == '\n' {
      flush()
    } else {
      cur.write_char(c)
    }
  }
  flush()
  toks
}

///|
/// Resolve the accumulated declaration into the GL type it describes: the base
/// type is the explicit `<ptype>` (else the lone non-qualifier word), wrapped
/// in one pointer level per `*`; the innermost carries the pointee's const-ness
/// (a `const` appearing before the first `*`).
fn Decl::to_gltype(self : Decl) -> GlType {
  let mut stars = 0
  let mut seen_star = false
  let mut pointee_const = false
  let words : Array[String] = []
  for t in tokenize_declarator(self.text.to_string()) {
    match t {
      Star => {
        stars += 1
        seen_star = true
      }
      Const => if !seen_star { pointee_const = true }
      Struct => ()
      Word(w) => words.push(w)
    }
  }
  // The base type is the explicit <ptype> if the registry tagged one, otherwise
  // the bare word(s) left in the declarator (e.g. "void").
  let ptype = self.ptype.to_string()
  let base = if ptype != "" { ptype } else { words.join(" ") }
  let mut ty : GlType = Base(base)
  for i in 0..<stars {
    ty = Ptr(ty, is_const=i == 0 && pointee_const)
  }
  ty
}

///|
/// Parse every `<command>` in the registry at `path`.
fn parse_commands(path : String) -> Array[Command] raise {
  let reader = @xml.Reader::from_file(path)
  let commands : Array[Command] = []
  let mut section = Section::Elsewhere
  let mut field = Field::Surrounding
  let mut proto = Decl::new() // the <proto>: return type + function name
  let mut param = Decl::new() // the <param> currently being read
  let mut params : Array[Param] = []
  while true {
    match reader.read_event() {
      @xml.Eof => break
      @xml.Start(el) =>
        match el.name {
          "command" => {
            section = Section::Elsewhere
            proto = Decl::new()
            params = []
          }
          "proto" => {
            section = Section::Proto
            field = Field::Surrounding
          }
          "param" => {
            section = Section::Param
            field = Field::Surrounding
            param = Decl::new()
          }
          "ptype" => field = Field::Ptype
          "name" => field = Field::Name
          _ => ()
        }
      @xml.Text(t) =>
        match section {
          Section::Proto => proto.feed(field, t)
          Section::Param => param.feed(field, t)
          Section::Elsewhere => ()
        }
      @xml.End(name) =>
        match name {
          "ptype" | "name" => field = Field::Surrounding
          "proto" => section = Section::Elsewhere
          "param" => {
            section = Section::Elsewhere
            params.push({ name: param.ident(), ty: param.to_gltype() })
          }
          "command" =>
            commands.push({
              name: proto.ident(),
              ret: proto.to_gltype(),
              params,
            })
          _ => ()
        }
      _ => ()
    }
  }
  commands
}
