///|
test "buffer byte sizes follow packed scalar storage" {
  let bytes : FixedArray[Byte] = [1, 2, 3]
  let shorts : FixedArray[UInt16] = [1, 2, 3]
  let floats : FixedArray[Float] = [1.0, 2.0, 3.0]
  let doubles : FixedArray[Double] = [1.0, 2.0, 3.0]
  inspect(gl_buffer_data_size(bytes), content="3")
  inspect(gl_buffer_data_size(shorts), content="6")
  inspect(gl_buffer_data_size(floats), content="12")
  inspect(gl_buffer_data_size(doubles), content="24")
}

///|
test "native borrows keep managed arrays alive for the call" {
  let values : FixedArray[Int] = [7, 8]
  let pointer_was_non_null = borrow_array(values, fn(pointer) {
    !pointer.is_null()
  })
  inspect(pointer_was_non_null, content="true")
  inspect(values[0], content="7")
  inspect(values[1], content="8")
}
