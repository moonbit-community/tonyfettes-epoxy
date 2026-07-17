///|
/// Scalar element types whose packed `FixedArray` representation can be copied
/// into an OpenGL buffer. This trait is sealed so user-defined reference types
/// cannot claim a native layout that MoonBit does not guarantee.
trait GlData {
  fn size_in_bytes() -> Int64
}

///|
pub impl GlData for Byte with fn size_in_bytes() {
  1L
}

///|
pub impl GlData for Int16 with fn size_in_bytes() {
  2L
}

///|
pub impl GlData for UInt16 with fn size_in_bytes() {
  2L
}

///|
pub impl GlData for Int with fn size_in_bytes() {
  4L
}

///|
pub impl GlData for UInt with fn size_in_bytes() {
  4L
}

///|
pub impl GlData for Int64 with fn size_in_bytes() {
  8L
}

///|
pub impl GlData for UInt64 with fn size_in_bytes() {
  8L
}

///|
pub impl GlData for Float with fn size_in_bytes() {
  4L
}

///|
pub impl GlData for Double with fn size_in_bytes() {
  8L
}

///|
fn[T : GlData] gl_buffer_data_size(data : FixedArray[T]) -> Int64 {
  data.length().to_int64() * T::size_in_bytes()
}

///|
let d_glBufferData : Dispatch = Dispatch::with_aliases("glBufferData", [
  "glBufferDataARB",
])

///|
let d_glBufferDataARB : Dispatch = Dispatch::with_aliases("glBufferDataARB", [
  "glBufferData",
])

///|
let d_glBufferSubData : Dispatch = Dispatch::with_aliases("glBufferSubData", [
  "glBufferSubDataARB",
])

///|
let d_glBufferSubDataARB : Dispatch = Dispatch::with_aliases(
  "glBufferSubDataARB",
  ["glBufferSubData"],
)

///|
/// Copy a packed scalar array into a new data store for the buffer currently
/// bound to `target`. The byte size is derived from `data`.
pub fn[T : GlData] gl_buffer_data(
  target : UInt,
  data : FixedArray[T],
  usage : UInt,
) -> Unit {
  let fp : FuncRef[(UInt, Int64, @pointer.Pointer[Unit], UInt) -> Unit] = d_glBufferData
    .get()
    .unsafe_into()
  let size = gl_buffer_data_size(data)
  @pointer.borrow_array(data, fn(data_pointer) {
    let raw : @pointer.Pointer[Unit] = data_pointer.cast()
    fp(target, size, raw, usage)
  })
}

///|
/// ARB spelling of `gl_buffer_data`.
pub fn[T : GlData] gl_buffer_data_arb(
  target : UInt,
  data : FixedArray[T],
  usage : UInt,
) -> Unit {
  let fp : FuncRef[(UInt, Int64, @pointer.Pointer[Unit], UInt) -> Unit] = d_glBufferDataARB
    .get()
    .unsafe_into()
  let size = gl_buffer_data_size(data)
  @pointer.borrow_array(data, fn(data_pointer) {
    let raw : @pointer.Pointer[Unit] = data_pointer.cast()
    fp(target, size, raw, usage)
  })
}

///|
/// Allocate an uninitialized data store for the buffer currently bound to
/// `target`. Use `gl_buffer_sub_data` or another OpenGL operation to fill it.
pub fn gl_buffer_allocate(target : UInt, size : Int64, usage : UInt) -> Unit {
  let fp : FuncRef[(UInt, Int64, @pointer.Pointer[Unit], UInt) -> Unit] = d_glBufferData
    .get()
    .unsafe_into()
  fp(target, size, @pointer.Pointer::null(), usage)
}

///|
/// ARB spelling of `gl_buffer_allocate`.
pub fn gl_buffer_allocate_arb(
  target : UInt,
  size : Int64,
  usage : UInt,
) -> Unit {
  let fp : FuncRef[(UInt, Int64, @pointer.Pointer[Unit], UInt) -> Unit] = d_glBufferDataARB
    .get()
    .unsafe_into()
  fp(target, size, @pointer.Pointer::null(), usage)
}

///|
/// Update part of the buffer currently bound to `target`. The byte size is
/// derived from `data`.
pub fn[T : GlData] gl_buffer_sub_data(
  target : UInt,
  offset : Int64,
  data : FixedArray[T],
) -> Unit {
  let fp : FuncRef[(UInt, Int64, Int64, @pointer.Pointer[Unit]) -> Unit] = d_glBufferSubData
    .get()
    .unsafe_into()
  let size = gl_buffer_data_size(data)
  @pointer.borrow_array(data, fn(data_pointer) {
    let raw : @pointer.Pointer[Unit] = data_pointer.cast()
    fp(target, offset, size, raw)
  })
}

///|
/// ARB spelling of `gl_buffer_sub_data`.
pub fn[T : GlData] gl_buffer_sub_data_arb(
  target : UInt,
  offset : Int64,
  data : FixedArray[T],
) -> Unit {
  let fp : FuncRef[(UInt, Int64, Int64, @pointer.Pointer[Unit]) -> Unit] = d_glBufferSubDataARB
    .get()
    .unsafe_into()
  let size = gl_buffer_data_size(data)
  @pointer.borrow_array(data, fn(data_pointer) {
    let raw : @pointer.Pointer[Unit] = data_pointer.cast()
    fp(target, offset, size, raw)
  })
}
