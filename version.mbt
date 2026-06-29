///|
/// epoxy's GL introspection API: the version/extension queries callers use to
/// branch on what the live context supports. Each wraps a `glGet*` entry point
/// and hands the reported string to the pure `@glinfo` parsers.

///|
/// The GL version of the current context, packed as `10 * major + minor`
/// (e.g. 21 for "2.1", 46 for "4.6"). Mirrors `epoxy_gl_version`: returns 0 when
/// the driver's `GL_VERSION` string cannot be parsed (a malformed-driver
/// sentinel — real contexts always report `major.minor`).
pub fn gl_version() -> Int {
  match @glinfo.parse_version(gl_get_string(GL_VERSION)) {
    Some(v) => v
    None => 0
  }
}

///|
/// Whether the current context is desktop GL (as opposed to OpenGL ES), decided
/// from the `GL_VERSION` string prefix. Mirrors `epoxy_is_desktop_gl`.
pub fn is_desktop_gl() -> Bool {
  @glinfo.is_desktop(gl_get_string(GL_VERSION))
}

///|
/// Whether the current context advertises extension `ext` (e.g.
/// "GL_ARB_vertex_array_object"). Mirrors `epoxy_has_gl_extension`: pre-3.0
/// contexts expose one space-separated `GL_EXTENSIONS` string, while 3.0+
/// contexts must be enumerated by index via `glGetStringi`.
pub fn has_gl_extension(ext : String) -> Bool {
  if gl_version() < 30 {
    @glinfo.extension_in_string(gl_get_string(GL_EXTENSIONS), ext)
  } else {
    let count : FixedArray[Int] = FixedArray::make(1, 0)
    gl_get_integerv(GL_NUM_EXTENSIONS, count)
    for i in 0..<count[0] {
      if gl_get_stringi(GL_EXTENSIONS, i.reinterpret_as_uint()) == ext {
        return true
      }
    }
    false
  }
}
