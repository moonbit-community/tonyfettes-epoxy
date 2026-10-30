///|
test "by-value scalar: ptype only, no declarator text" {
  inspect(@cdecl.parse_declarator("GLenum", ""), content="GLenum")
}

///|
test "input pointer: const before the star marks the pointee const" {
  inspect(
    @cdecl.parse_declarator("GLfloat", "const  *"),
    content="const GLfloat*",
  )
}

///|
test "output pointer: no const" {
  inspect(@cdecl.parse_declarator("GLuint", " *"), content="GLuint*")
}

///|
test "bare base type (no ptype) is taken from the declarator text" {
  inspect(@cdecl.parse_declarator("", "void *"), content="void*")
  inspect(@cdecl.parse_declarator("", "void"), content="void")
}

///|
test "trailing const (const pointer) does not mark the pointee const" {
  inspect(@cdecl.parse_declarator("GLfloat", " * const"), content="GLfloat*")
}

///|
test "struct keyword is dropped; the tagged name is the base" {
  inspect(@cdecl.parse_declarator("", "struct _cl_event"), content="_cl_event")
}

///|
test "double pointer nests" {
  inspect(
    @cdecl.parse_declarator("GLchar", " *const*"),
    content="const GLchar**",
  )
}

///|
test "base_name sees through pointers" {
  inspect(
    @cdecl.parse_declarator("GLubyte", "const  *").base_name(),
    content="GLubyte",
  )
}
