///|
test "hand-wrapped entry points keep a distinct implementation name" {
  inspect(
    generated_fn_name("glVertexAttribPointer"),
    content="gl_vertex_attrib_pointer_raw",
  )
  inspect(
    generated_fn_name("glVertexAttribPointerARB"),
    content="gl_vertex_attrib_pointer_arb_raw",
  )
  inspect(generated_fn_name("glDrawArrays"), content="gl_draw_arrays")
}

///|
test "hand-wrapped entry points render private raw-pointer helpers" {
  let command : Command = {
    name: "glVertexAttribPointer",
    ret: @cdecl.Base("void"),
    params: [
      { name: "index", ty: @cdecl.Base("GLuint") },
      { name: "size", ty: @cdecl.Base("GLint") },
      { name: "type", ty: @cdecl.Base("GLenum") },
      { name: "normalized", ty: @cdecl.Base("GLboolean") },
      { name: "stride", ty: @cdecl.Base("GLsizei") },
      { name: "pointer", ty: @cdecl.Ptr(@cdecl.Base("void"), is_const=true) },
    ],
    aliases: [],
  }
  guard command.signature() is Some(signature) else {
    fail("glVertexAttribPointer should have a supported signature")
  }
  let generated = render(command, signature, ["glVertexAttribPointerARB"]).moonbit
  assert_true(
    generated.contains(
      "fn gl_vertex_attrib_pointer_raw(index : UInt, size : Int, type_ : UInt, normalized : Bool, stride : Int, pointer : @c.Pointer[Unit])",
    ),
  )
  assert_false(generated.contains("pub fn gl_vertex_attrib_pointer_raw"))
  assert_false(generated.contains("@c.borrow_bytes(pointer"))
  assert_true(
    generated.contains("fp(index, size, type_, normalized, stride, pointer)"),
  )
}
