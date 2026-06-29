///|
/// Parsing of the small C-declarator fragments the Khronos registry uses in
/// command signatures (e.g. `const GLfloat *`, `void *`, `struct _cl_event`).
/// Pure and dependency-free, so it can be unit-tested in isolation.

///|
/// The parser's output AST: a parameter/return type as *written in the GL
/// registry*. Leaves (`Base`) are GL-registry spellings — `GLfloat`, `GLenum`,
/// `void` — so this is purely syntactic, with no notion of size, ABI, or C
/// spelling. Translating it to a real C type is the generator's job (it looks
/// each leaf up in the type table; see the generator's `Declarator`).
///
/// `is_const` records whether the pointee is `const` (the input-vs-output
/// signal); `const` is a reserved word, hence the label name.
pub(all) enum Declarator {
  Base(String)
  Ptr(Declarator, is_const~ : Bool)
}

///|
/// Render a GL type the way it reads in C, used for diagnostics and tests:
/// `Ptr(Base("GLfloat"), is_const=true)` -> `const GLfloat*`.
pub impl Show for Declarator with fn output(self, logger) {
  match self {
    Base(name) => logger.write_string(name)
    Ptr(inner, is_const~) => {
      if is_const {
        logger.write_string("const ")
      }
      inner.output(logger)
      logger.write_string("*")
    }
  }
}

///|
/// The innermost base typedef name (sees through pointers), e.g. the `GLubyte`
/// in `const GLubyte *`.
pub fn Declarator::base_name(self : Declarator) -> String {
  match self {
    Base(name) => name
    Ptr(inner, ..) => inner.base_name()
  }
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
/// Classify a lexed word as a keyword token or a plain type name.
fn Token::of_word(w : String) -> Token {
  match w {
    "const" => Const
    "struct" => Struct
    _ => Word(w)
  }
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
      toks.push(Token::of_word(w))
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
/// Parse a declarator into the GL type it describes. `ptype` is the registry's
/// explicit `<ptype>` (empty when the base type is bare text); `text` is the
/// surrounding declarator (qualifiers, stars, and any bare base word).
///
/// Builds the type outward from the base leaf: one pointer level per `*`, with
/// a `const` attached to the next pointer (so a `const` before the first `*`
/// marks the pointee const).
pub fn parse_declarator(ptype : String, text : String) -> Declarator {
  let mut ty : Declarator = Base(ptype)
  let mut pending_const = false
  for t in tokenize_declarator(text) {
    match t {
      Word(w) => if ptype == "" { ty = Base(w) }
      Const => pending_const = true
      Star => {
        ty = Ptr(ty, is_const=pending_const)
        pending_const = false
      }
      Struct => () // keyword, not part of the type name — ignore
    }
  }
  ty
}
