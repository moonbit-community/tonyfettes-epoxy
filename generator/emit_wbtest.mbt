///|
test "hand-wrapped entry points keep an explicit raw binding" {
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
