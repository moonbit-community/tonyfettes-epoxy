///|
/// Streaming parser that turns the Khronos registry `<command>` entries into
/// structured `Command` records. Only the command signatures are needed for
/// dispatch; everything else (enums, features, extensions) is skipped here.

///|
priv struct Param {
  name : String
  ty : @cdecl.CType
}

///|
priv struct Command {
  name : String
  ret : @cdecl.CType
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
/// The accumulated declaration as the GL type it describes (declarator parsing
/// lives in the `cdecl` package).
fn Decl::to_ctype(self : Decl) -> @cdecl.CType {
  @cdecl.parse_declarator(self.ptype.to_string(), self.text.to_string())
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
            params.push({ name: param.ident(), ty: param.to_ctype() })
          }
          "command" =>
            commands.push({
              name: proto.ident(),
              ret: proto.to_ctype(),
              params,
            })
          _ => ()
        }
      _ => ()
    }
  }
  commands
}
