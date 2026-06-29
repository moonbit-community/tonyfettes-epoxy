///|
test "scalar lookup maps to the right MoonBit type" {
  let m = lookup("GLenum").unwrap()
  inspect(m.moonbit_type, content="UInt")
  inspect(m.category, content="Scalar")
}

///|
test "pointer-width offset is Int64, never narrowed" {
  let m = lookup("GLsizeiptr").unwrap()
  inspect(m.moonbit_type, content="Int64")
  inspect(m.category, content="PtrSized")
}

///|
test "unknown type returns None so the generator can complain" {
  inspect(lookup("GLnope"), content="None")
}

///|
test "every typedef seen in gl.xml command signatures is covered" {
  // The full list of <ptype> names that actually appear in gl.xml command
  // signatures (excluding bare `struct _cl_*`, which are extension-only).
  let needed = [
    "GLenum", "GLuint", "GLint", "GLsizei", "GLfloat", "GLdouble", "GLfixed",
    "GLboolean", "GLshort", "GLuint64", "GLintptr", "GLubyte", "GLchar",
    "GLbyte", "GLhalfNV", "GLbitfield", "GLuint64EXT", "GLsizeiptr",
    "GLint64EXT", "GLint64", "GLushort", "GLhandleARB", "GLsync",
    "GLvdpauSurfaceNV", "GLclampf", "GLcharARB", "GLeglImageOES",
    "GLsizeiptrARB", "GLintptrARB", "GLeglClientBufferEXT", "GLclampx",
    "GLclampd", "GLDEBUGPROC", "GLDEBUGPROCKHR", "GLDEBUGPROCARB",
    "GLDEBUGPROCAMD", "GLVULKANPROCNV",
  ]
  let missing = needed.filter(fn(t) { lookup(t) is None })
  inspect(missing, content="[]")
}
