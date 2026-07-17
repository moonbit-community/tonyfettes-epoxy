///|
test "hand-written commands are excluded from generated bindings" {
  assert_true(is_hand_written_command("glBufferData"))
  assert_true(is_hand_written_command("glBufferDataARB"))
  assert_true(is_hand_written_command("glBufferSubData"))
  assert_true(is_hand_written_command("glBufferSubDataARB"))
  assert_false(is_hand_written_command("glVertexAttribPointer"))
  assert_false(is_hand_written_command("glVertexAttribPointerARB"))
  assert_false(is_hand_written_command("glDrawArrays"))
}

///|
test "array-buffer offset policy is an exact allow-list" {
  assert_true(is_array_buffer_offset_param("glVertexPointer", "pointer"))
  assert_true(
    is_array_buffer_offset_param("glVertexAttribIPointerEXT", "pointer"),
  )
  assert_true(is_array_buffer_offset_param("glVariantPointerEXT", "addr"))
  assert_true(is_array_buffer_offset_param("glWeightPointerOES", "pointer"))
  assert_false(is_array_buffer_offset_param("glVertexPointerEXT", "pointer"))
  assert_false(
    is_array_buffer_offset_param("glVertexAttribPointerNV", "pointer"),
  )
  assert_false(
    is_array_buffer_offset_param("glMatrixIndexPointerARB", "pointer"),
  )
  assert_false(is_array_buffer_offset_param("glFeedbackBuffer", "buffer"))
}

///|
test "array-buffer pointers render as offsets without a borrow scope" {
  let xml =
    #|<registry><commands><command><proto>void <name>glVertexAttribIPointer</name></proto><param><ptype>GLuint</ptype> <name>index</name></param><param><ptype>GLint</ptype> <name>size</name></param><param><ptype>GLenum</ptype> <name>type</name></param><param><ptype>GLsizei</ptype> <name>stride</name></param><param>const void *<name>pointer</name></param></command></commands></registry>
  guard parse_commands(xml) is [command] else {
    fail("expected one parsed command")
  }
  guard command.signature() is Some(sig) else {
    fail("expected a supported signature")
  }
  let output = render(command, sig, []).moonbit
  inspect(output.contains("offset : Int64"), content="true")
  inspect(
    output.contains("@pointer.Pointer::unsafe_from_int64(offset)"),
    content="true",
  )
  inspect(output.contains("@pointer.borrow"), content="false")
}
