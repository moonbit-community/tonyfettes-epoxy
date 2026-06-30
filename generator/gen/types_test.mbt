///|
test "scalar lookup gives the right MoonBit type" {
  guard lookup("GLenum") is Some(m) else { fail("GLenum should be mapped") }
  inspect(m.m_type.moonbit(), content="UInt")
}

///|
test "pointer-width type resolves to Int64 MoonBit" {
  guard lookup("GLsizeiptr") is Some(m) else {
    fail("GLsizeiptr should be mapped")
  }
  inspect(m.m_type.moonbit(), content="Int64")
}

///|
test "GLboolean and GLubyte share a C type but differ in MoonBit" {
  guard lookup("GLboolean") is Some(b) else {
    fail("GLboolean should be mapped")
  }
  guard lookup("GLubyte") is Some(ub) else { fail("GLubyte should be mapped") }
  inspect(b.m_type.moonbit(), content="Bool")
  inspect(ub.m_type.moonbit(), content="Int")
}

///|
test "FuncRef param spelling: scalars keep their type, arrays/bytes are @c.Pointer" {
  inspect((UInt : MType).funcref_type(), content="UInt")
  inspect((Handle("GLsync") : MType).funcref_type(), content="GLsync")
  inspect((Bytes : MType).funcref_type(), content="@c.Pointer[Byte]")
  inspect((Array(Int) : MType).funcref_type(), content="@c.Pointer[Int]")
  inspect((Array(Int16) : MType).funcref_type(), content="@c.Pointer[Int16]")
  // the const GLchar *const * of glShaderSource: a pointer to the char* run
  inspect((Array(Bytes) : MType).funcref_type(), content="@c.Pointer[Bytes]")
}

///|
test "sub-word returns are narrowed; full-width returns pass through" {
  // GLboolean (unsigned char) exposed as Bool -> mask then compare
  inspect(narrow_of(Byte, Bool) is BoolU8, content="true")
  // GLubyte (unsigned char) exposed as Int -> zero-extend the low byte
  inspect(narrow_of(Byte, Int) is MaskU8, content="true")
  inspect(narrow_of(Short, Int) is SignU16, content="true")
  inspect(narrow_of(UShort, Int) is MaskU16, content="true")
  // full-width scalars and handles need no fixup
  inspect(narrow_of(UInt, UInt) is None, content="true")
  inspect(narrow_of(OpaquePtr, Handle("GLsync")) is None, content="true")
}

///|
test "FuncRef return type: sub-word comes back as Int, others natural" {
  inspect(funcref_ret_type(Byte, Bool), content="Int")
  inspect(funcref_ret_type(Short, Int), content="Int")
  inspect(funcref_ret_type(UInt, UInt), content="UInt")
  inspect(funcref_ret_type(OpaquePtr, Handle("GLsync")), content="GLsync")
}

///|
test "opaque object handles map to a named external pointer" {
  // GLsync &c. cross the FFI as a bare pointer but keep a distinct MoonBit type.
  guard lookup("GLsync") is Some(s) else { fail("GLsync should be mapped") }
  inspect(s.m_type.moonbit(), content="GLsync")
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
