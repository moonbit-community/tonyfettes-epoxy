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
