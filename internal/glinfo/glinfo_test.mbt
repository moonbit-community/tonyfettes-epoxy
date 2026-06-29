///|
test "desktop GL version string" {
  // Apple's "2.1 Metal - 90.5": major.minor at the very front
  debug_inspect(@glinfo.parse_version("2.1 Metal - 90.5"), content="Some(21)")
}

///|
test "version with a release component keeps only major.minor" {
  debug_inspect(@glinfo.parse_version("4.6.0 NVIDIA 535.0"), content="Some(46)")
}

///|
test "GLES version string skips the leading prefix" {
  debug_inspect(
    @glinfo.parse_version("OpenGL ES 3.2 Mesa 24.0"),
    content="Some(32)",
  )
  debug_inspect(@glinfo.parse_version("OpenGL ES-CM 1.1"), content="Some(11)")
}

///|
test "two-digit minor parses fully" {
  debug_inspect(@glinfo.parse_version("4.10 foo"), content="Some(50)")
}

///|
test "unparseable version strings yield None" {
  debug_inspect(@glinfo.parse_version(""), content="None")
  debug_inspect(@glinfo.parse_version("Metal"), content="None")
  debug_inspect(@glinfo.parse_version("3 no dot"), content="None")
}

///|
test "desktop vs GLES detection" {
  inspect(@glinfo.is_desktop("2.1 Metal - 90.5"), content="true")
  inspect(@glinfo.is_desktop("4.6.0 NVIDIA"), content="true")
  inspect(@glinfo.is_desktop("OpenGL ES 3.2 Mesa"), content="false")
}

///|
test "extension membership is whole-token and prefix-safe" {
  let list = "GL_ARB_foo GL_ARB_foobar GL_EXT_baz"
  inspect(@glinfo.extension_in_string(list, "GL_ARB_foo"), content="true")
  inspect(@glinfo.extension_in_string(list, "GL_EXT_baz"), content="true")
  // a prefix of a real entry must not count as present
  inspect(@glinfo.extension_in_string(list, "GL_ARB_fooba"), content="false")
  inspect(@glinfo.extension_in_string(list, "GL_MISSING"), content="false")
  inspect(@glinfo.extension_in_string("", "GL_ARB_foo"), content="false")
  inspect(@glinfo.extension_in_string(list, ""), content="false")
}
