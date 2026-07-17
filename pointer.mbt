///|
/// Package-private representation of a native pointer. It exists only at the
/// FFI boundary; public OpenGL APIs expose owned MoonBit values or byte offsets.
#external
priv type Pointer[_]

///|
fn[T, U] Pointer::cast(self : Pointer[T]) -> Pointer[U] = "%identity"

///|
extern "c" fn epoxy_pointer_null() -> Pointer[Unit] = "epoxy_pointer_null"

///|
extern "c" fn epoxy_pointer_is_null(pointer : Pointer[Unit]) -> Bool = "epoxy_pointer_is_null"

///|
fn[T] Pointer::null() -> Pointer[T] {
  epoxy_pointer_null().cast()
}

///|
fn[T] Pointer::is_null(self : Pointer[T]) -> Bool {
  epoxy_pointer_is_null(self.cast())
}

///|
fn[T] pointer_from_array(array : FixedArray[T]) -> Pointer[T] = "%identity"

///|
fn pointer_from_bytes(bytes : Bytes) -> Pointer[Byte] = "%identity"

///|
fn[T] pointer_into_array(pointer : Pointer[T]) -> FixedArray[T] = "%identity"

///|
fn pointer_into_bytes(pointer : Pointer[Byte]) -> Bytes = "%identity"

///|
fn[T] pointer_into(pointer : Pointer[Unit]) -> T = "%identity"

///|
/// Keep an array's managed backing storage alive while a native function uses
/// its data pointer.
fn[T, R] borrow_array(
  array : FixedArray[T],
  use_pointer : (Pointer[T]) -> R,
) -> R {
  let pointer = pointer_from_array(array)
  let result = use_pointer(pointer)
  let _ : FixedArray[T] = pointer_into_array(pointer)
  result
}

///|
/// Keep a byte string's managed backing storage alive while a native function
/// uses its data pointer.
fn[R] borrow_bytes(bytes : Bytes, use_pointer : (Pointer[Byte]) -> R) -> R {
  let pointer = pointer_from_bytes(bytes)
  let result = use_pointer(pointer)
  let _ : Bytes = pointer_into_bytes(pointer)
  result
}
