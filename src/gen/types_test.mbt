///|
test "scalar lookup gives the right C and MoonBit types" {
  let m = lookup("GLenum").unwrap()
  inspect(m.c_type.c(), content="unsigned int")
  inspect(m.m_type.moonbit(), content="UInt")
}

///|
test "pointer-width type resolves to intptr-sized C / Int64 MoonBit" {
  let m = lookup("GLsizeiptr").unwrap()
  inspect(m.c_type.c(), content="ssize_t")
  inspect(m.m_type.moonbit(), content="Int64")
}

///|
test "GLboolean and GLubyte share a C type but differ in MoonBit" {
  inspect(lookup("GLboolean").unwrap().c_type.c(), content="unsigned char")
  inspect(lookup("GLubyte").unwrap().c_type.c(), content="unsigned char")
  inspect(lookup("GLboolean").unwrap().m_type.moonbit(), content="Bool")
  inspect(lookup("GLubyte").unwrap().m_type.moonbit(), content="Int")
}

///|
test "MoonBit ABI spelling" {
  inspect(lookup("GLuint64").unwrap().m_type.c_abi(), content="uint64_t")
  inspect(lookup("GLfloat").unwrap().m_type.c_abi(), content="float")
}

///|
test "opaque handles and callbacks are unsupported (absent from the table)" {
  inspect(lookup("GLsync") is None, content="true")
  inspect(lookup("GLDEBUGPROC") is None, content="true")
  inspect(lookup("GLhandleARB") is None, content="true")
}
