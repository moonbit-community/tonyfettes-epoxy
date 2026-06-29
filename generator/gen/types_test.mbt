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
test "16-bit array element types are packed int16_t/uint16_t" {
  inspect((Array(Int16) : MType).moonbit(), content="FixedArray[Int16]")
  inspect((Array(Int16) : MType).c_abi(), content="int16_t *")
  inspect((Array(UInt16) : MType).moonbit(), content="FixedArray[UInt16]")
  inspect((Array(UInt16) : MType).c_abi(), content="uint16_t *")
}

///|
test "opaque object handles map to a named external pointer" {
  // GLsync &c. cross the FFI as a bare pointer but keep a distinct MoonBit type.
  guard lookup("GLsync") is Some(s) else { fail("GLsync should be mapped") }
  inspect(s.c_type.c(), content="void *")
  inspect(s.m_type.moonbit(), content="GLsync")
  inspect(s.m_type.c_abi(), content="void *")
  guard lookup("GLeglImageOES") is Some(egl) else {
    fail("GLeglImageOES should be mapped")
  }
  inspect(egl.m_type.moonbit(), content="GLeglImageOES")
}

///|
test "callbacks and platform-variant handles stay unsupported (absent)" {
  // GLhandleARB is unsigned int / Apple void * — a split ABI we won't miscompile.
  inspect(lookup("GLDEBUGPROC") is None, content="true")
  inspect(lookup("GLhandleARB") is None, content="true")
}

///|
test "const placement: west-const for scalar pointees, east-const past inner stars" {
  // a single-level const pointer keeps the idiomatic west-const spelling
  inspect((Pointer(Char, is_const=true) : CType).c(), content="const char *")
  // a plain out-pointer carries no const
  inspect((Pointer(Int, is_const=false) : CType).c(), content="int *")
  // const char *const * — the `char **` of glShaderSource's string param:
  // each const lands where it reads correctly, never `const const ... * *`
  inspect(
    (Pointer(Pointer(Char, is_const=true), is_const=true) : CType).c(),
    content="const char * const *",
  )
}
