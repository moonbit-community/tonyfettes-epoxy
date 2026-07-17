///|
test "hand-written commands are excluded from generated bindings" {
  assert_true(is_hand_written_command("glBufferData"))
  assert_true(is_hand_written_command("glBufferDataARB"))
  assert_true(is_hand_written_command("glBufferSubData"))
  assert_true(is_hand_written_command("glBufferSubDataARB"))
  assert_true(is_hand_written_command("glVertexAttribPointer"))
  assert_true(is_hand_written_command("glVertexAttribPointerARB"))
  assert_false(is_hand_written_command("glDrawArrays"))
}
