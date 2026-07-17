///|
/// Native pointer representation used only by epoxy's internal FFI packages.
#external
type Pointer[_]

///|
pub fn[T, U] Pointer::cast(self : Pointer[T]) -> Pointer[U] = "%identity"

///|
extern "c" fn epoxy_pointer_null() -> Pointer[Unit] = "epoxy_pointer_null"

///|
#borrow(pointer)
extern "c" fn epoxy_pointer_is_null(pointer : Pointer[Unit]) -> Bool = "epoxy_pointer_is_null"

///|
extern "c" fn epoxy_pointer_from_int64(value : Int64) -> Pointer[Unit] = "epoxy_pointer_from_int64"

///|
pub fn[T] Pointer::null() -> Pointer[T] {
  epoxy_pointer_null().cast()
}

///|
pub fn[T] Pointer::is_null(self : Pointer[T]) -> Bool {
  epoxy_pointer_is_null(self.cast())
}

///|
pub fn Pointer::unsafe_from_int64(value : Int64) -> Pointer[Unit] {
  epoxy_pointer_from_int64(value)
}

///|
pub fn[T] Pointer::unsafe_from_array(array : FixedArray[T]) -> Pointer[T] = "%identity"

///|
pub fn Pointer::unsafe_from_bytes(bytes : Bytes) -> Pointer[Byte] = "%identity"

///|
pub fn[T] Pointer::unsafe_into_array(self : Pointer[T]) -> FixedArray[T] = "%identity"

///|
pub fn Pointer::unsafe_into_bytes(self : Pointer[Byte]) -> Bytes = "%identity"

///|
pub fn[T] Pointer::unsafe_into(self : Pointer[Unit]) -> T = "%identity"

///|
/// Keep an array's managed backing storage alive while a native function uses
/// its data pointer.
pub fn[T, R] borrow_array(
  array : FixedArray[T],
  use_pointer : (Pointer[T]) -> R,
) -> R {
  let pointer = Pointer::unsafe_from_array(array)
  let result = use_pointer(pointer)
  let _ : FixedArray[T] = pointer.unsafe_into_array()
  result
}

///|
/// Keep a byte string's managed backing storage alive while a native function
/// uses its data pointer.
pub fn[R] borrow_bytes(bytes : Bytes, use_pointer : (Pointer[Byte]) -> R) -> R {
  let pointer = Pointer::unsafe_from_bytes(bytes)
  let result = use_pointer(pointer)
  let _ : Bytes = pointer.unsafe_into_bytes()
  result
}
