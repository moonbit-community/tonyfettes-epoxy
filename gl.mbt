///|
/// Client-side data accepted by `gl_vertex_attrib_pointer`.
///
/// Each constructor couples the OpenGL `type` token to a MoonBit array with
/// the matching in-memory representation, so callers cannot accidentally pass
/// (for example) `GL_FLOAT` alongside integer storage. OpenGL retains the raw
/// pointer after this call; the backing array must remain alive until the draw
/// that consumes it has completed.
pub(all) enum VertexAttribPointerData {
  BYTE(FixedArray[Byte])
  UNSIGNED_BYTE(FixedArray[Byte])
  SHORT(FixedArray[Int16])
  UNSIGNED_SHORT(FixedArray[UInt16])
  INT(FixedArray[Int])
  UNSIGNED_INT(FixedArray[UInt])
  FLOAT(FixedArray[Float])
  DOUBLE(FixedArray[Double])
  HALF_FLOAT(FixedArray[UInt16])
  FIXED(FixedArray[Int])
  UNSIGNED_INT_2_10_10_10_REV(FixedArray[UInt])
  UNSIGNED_INT_2_10_10_10_REV_EXT(FixedArray[UInt])
  UNSIGNED_INT_10F_11F_11F_REV(FixedArray[UInt])
  INT_2_10_10_10_REV(FixedArray[Int])
}

///|
/// Invoke one `glVertexAttribPointer` entry point after deriving its raw GL
/// type and pointer ABI from the data constructor. Core and ARB wrappers share
/// this complete transition; only their private generated helper differs.
fn call_vertex_attrib_pointer(
  call_raw : (UInt, Int, UInt, Bool, Int, @c.Pointer[Unit]) -> Unit,
  index : UInt,
  size : Int,
  normalized : Bool,
  stride : Int,
  pointer : VertexAttribPointerData,
) -> Unit {
  match pointer {
    BYTE(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_BYTE,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    UNSIGNED_BYTE(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_UNSIGNED_BYTE,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    SHORT(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_SHORT,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    UNSIGNED_SHORT(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_UNSIGNED_SHORT,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    INT(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_INT,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    UNSIGNED_INT(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_UNSIGNED_INT,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    FLOAT(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_FLOAT,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    DOUBLE(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_DOUBLE,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    HALF_FLOAT(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_HALF_FLOAT,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    FIXED(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_FIXED,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    UNSIGNED_INT_2_10_10_10_REV(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_UNSIGNED_INT_2_10_10_10_REV,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    UNSIGNED_INT_2_10_10_10_REV_EXT(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_UNSIGNED_INT_2_10_10_10_REV_EXT,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    UNSIGNED_INT_10F_11F_11F_REV(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_UNSIGNED_INT_10F_11F_11F_REV,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
    INT_2_10_10_10_REV(data) =>
      @c.borrow_array(data, fn(data_pointer) {
        call_raw(
          index,
          size,
          GL_INT_2_10_10_10_REV,
          normalized,
          stride,
          data_pointer.cast_to_unit(),
        )
      })
  }
}

///|
/// Define one client-side vertex attribute array. The backing array inside
/// `pointer` must remain alive until OpenGL has consumed it in a draw call.
pub fn gl_vertex_attrib_pointer(
  index : UInt,
  size : Int,
  normalized : Bool,
  stride : Int,
  pointer : VertexAttribPointerData,
) -> Unit {
  call_vertex_attrib_pointer(
    gl_vertex_attrib_pointer_raw, index, size, normalized, stride, pointer,
  )
}

///|
/// ARB spelling of `gl_vertex_attrib_pointer` with the same type-safe data
/// coupling and lifetime requirement.
pub fn gl_vertex_attrib_pointer_arb(
  index : UInt,
  size : Int,
  normalized : Bool,
  stride : Int,
  pointer : VertexAttribPointerData,
) -> Unit {
  call_vertex_attrib_pointer(
    gl_vertex_attrib_pointer_arb_raw, index, size, normalized, stride, pointer,
  )
}
