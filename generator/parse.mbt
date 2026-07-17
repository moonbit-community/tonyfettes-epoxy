///|
/// Streaming parser that turns the Khronos registry `<command>` entries into
/// structured `Command` records. Only the command signatures are needed for
/// dispatch; everything else (enums, features, extensions) is skipped here.

///|
priv struct Param {
  name : String
  ty : @cdecl.Declarator
}

///|
priv struct Command {
  name : String
  ret : @cdecl.Declarator
  params : Array[Param]
  /// The names this command declares itself an alias of (`<alias name="..."/>`);
  /// the generator unions these into resolution groups.
  aliases : Array[String]
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
  {
    ptype: StringBuilder::new(),
    name: StringBuilder::new(),
    text: StringBuilder::new(),
  }
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
fn Decl::to_ctype(self : Decl) -> @cdecl.Declarator {
  @cdecl.parse_declarator(self.ptype.to_string(), self.text.to_string())
}

///|
/// How an enum's literal value is typed in MoonBit. Almost every GL enum is a
/// `GLenum`/`GLbitfield` (unsigned 32-bit); a couple of 64-bit sentinels and a
/// handful of negative `*_NV` markers are the only exceptions.
priv enum EnumKind {
  Unsigned // UInt — GLenum / GLbitfield, the overwhelming default
  Unsigned64 // UInt64 — `type="ull"` (GL_TIMEOUT_IGNORED &c.)
  Signed // Int — negative sentinels (GL_SKIP_COMPONENTS*_NV, GL_NEXT_BUFFER_NV)
}

///|
/// A resolved GL enum definition: its `GL_*` name, the literal exactly as the
/// registry spells it (hex/decimal/negative), and how to type it.
priv struct EnumDef {
  name : String
  value : String
  kind : EnumKind
}

///|
/// Parse every GL enum *definition* in the registry `content`. Definitions live
/// in `<enums>` blocks and carry both `value` and `name`; the bare
/// `<enum name="..."/>` references inside `<feature>`/`<extension>` requires
/// have no `value`, so filtering on `value` excludes them. Deduplicated by name
/// (a name is defined once, but may be referenced many times) — and no name in
/// the registry maps to two different values, so first-wins is unambiguous.
fn parse_enums(content : String) -> Array[EnumDef] raise {
  let reader = @xml.Reader::from_string(content)
  let out : Array[EnumDef] = []
  let seen : Map[String, Bool] = Map([])
  while true {
    match reader.read_event() {
      @xml.Eof => break
      @xml.Empty(el) =>
        if el.name == "enum" &&
          el.get("value") is Some(value) &&
          el.get("name") is Some(name) &&
          !seen.contains(name) {
          seen[name] = true
          let kind = if value.has_prefix("-") {
            EnumKind::Signed
          } else if el.get("type") is Some("ull") {
            EnumKind::Unsigned64
          } else {
            EnumKind::Unsigned
          }
          out.push({ name, value, kind })
        }
      _ => ()
    }
  }
  out
}

///|
/// Parse every `<command>` in the already-loaded registry XML `content`. The
/// file read is the caller's job (done with async IO), so this stays pure over
/// an in-memory string — no filesystem dependency of its own.
fn parse_commands(content : String) -> Array[Command] raise {
  let reader = @xml.Reader::from_string(content)
  let commands : Array[Command] = []
  let mut section = Section::Elsewhere
  let mut field = Field::Surrounding
  let mut proto = Decl::new() // the <proto>: return type + function name
  let mut param = Decl::new() // the <param> currently being read
  let mut params : Array[Param] = []
  let mut aliases : Array[String] = []
  while true {
    match reader.read_event() {
      @xml.Eof => break
      @xml.Empty(el) =>
        // `<alias name="..."/>` is a self-closing element inside <command>.
        if el.name == "alias" && section is Section::Elsewhere {
          if el.get("name") is Some(target) {
            aliases.push(target)
          }
        }
      @xml.Start(el) =>
        match el.name {
          "command" => {
            section = Section::Elsewhere
            proto = Decl::new()
            params = []
            aliases = []
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
              aliases,
            })
          _ => ()
        }
      _ => ()
    }
  }
  commands
}
