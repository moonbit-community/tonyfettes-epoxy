///|
/// Streaming parser that turns the Khronos registry `<command>` entries into
/// structured `Command` records. Only the command signatures are needed for
/// dispatch; everything else (enums, features, extensions) is skipped here.

///|
priv struct Param {
  name : String
  gltype : String
  pointer : Bool
}

///|
priv struct Command {
  name : String
  ret : String
  ret_pointer : Bool
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
  fn finalize_type(ptype : String, text : String) -> (String, Bool) {
    let pointer = text.contains("*")
    let base = if ptype != "" { ptype } else { text.replace(old="*", new="") }
    // strip qualifiers/whitespace ("const", "struct", spaces)
    let cleaned = base
      .replace(old="const", new="")
      .replace(old="struct", new="")
      .trim(chars=" \t\n")
      .to_owned()
    (cleaned, pointer)
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
            let (gltype, pointer) = finalize_type(p_ptype, p_text)
            params.push({ name: p_name.trim(chars=" ").to_owned(), gltype, pointer })
          }
          "command" => {
            let (ret, ret_pointer) = finalize_type(proto_ptype, proto_text)
            commands.push({
              name: proto_name.trim(chars=" ").to_owned(),
              ret,
              ret_pointer,
              params,
            })
          }
          _ => ()
        }
      _ => ()
    }
  }
  commands
}
