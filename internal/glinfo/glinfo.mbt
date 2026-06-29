///|
/// Interpreting the strings a GL implementation reports about itself — the
/// `GL_VERSION` string and the `GL_EXTENSIONS` list — into the forms epoxy's
/// query API exposes. Pure and dependency-free, so the fiddly string handling
/// can be unit-tested without a live GL context; the `epoxy` package supplies
/// the actual `glGetString` calls.

///|
fn is_ascii_digit(code : Int) -> Bool {
  code >= '0' && code <= '9'
}

///|
/// Parse a `GL_VERSION` string into epoxy's packed form, `10 * major + minor`
/// (so `"2.1 Metal - 90.5"` -> 21, `"OpenGL ES 3.2 ..."` -> 32, `"4.6.0 ..."`
/// -> 46). Mirrors epoxy: skip any leading non-digits (the `OpenGL ES` prefix),
/// then read `major.minor`. Returns `None` when no `major.minor` is present.
pub fn parse_version(version_string : String) -> Int? {
  let n = version_string.length()
  let mut i = 0
  // skip to the first digit (past an "OpenGL ES " / "OpenGL ES-CM " prefix)
  while i < n && !is_ascii_digit(version_string[i].to_int()) {
    i += 1
  }
  // read the major run
  let mut major = 0
  let mut saw_major = false
  while i < n && is_ascii_digit(version_string[i].to_int()) {
    major = major * 10 + (version_string[i].to_int() - '0')
    saw_major = true
    i += 1
  }
  // require the '.' separator
  guard saw_major && i < n && version_string[i].to_int() == '.' else {
    return None
  }
  i += 1
  // read the minor run
  let mut minor = 0
  let mut saw_minor = false
  while i < n && is_ascii_digit(version_string[i].to_int()) {
    minor = minor * 10 + (version_string[i].to_int() - '0')
    saw_minor = true
    i += 1
  }
  guard saw_minor else { return None }
  Some(10 * major + minor)
}

///|
/// epoxy treats an implementation as desktop GL unless its `GL_VERSION` string
/// is prefixed with `"OpenGL ES"` (the GLES marker).
pub fn is_desktop(version_string : String) -> Bool {
  !version_string.has_prefix("OpenGL ES")
}

///|
/// Whether `ext` appears as a whole entry in a space-separated `GL_EXTENSIONS`
/// list. Matches epoxy's prefix-safe scan: `"GL_foo"` must not be reported as
/// present merely because `"GL_foobar"` is in the list.
pub fn extension_in_string(extension_list : String, ext : String) -> Bool {
  if ext == "" {
    return false
  }
  for token in extension_list.split(" ") {
    if token == ext[:] {
      return true
    }
  }
  false
}
