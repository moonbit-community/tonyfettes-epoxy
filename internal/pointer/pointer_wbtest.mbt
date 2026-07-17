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
