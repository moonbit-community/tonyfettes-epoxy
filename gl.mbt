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
/// this complete transition; only their dispatch slot differs.
fn call_vertex_attrib_pointer(
  dispatch : Dispatch,
  index : UInt,
  size : Int,
  normalized : Bool,
  stride : Int,
  pointer : VertexAttribPointerData,
) -> Unit {
  let address = dispatch.get()
  match pointer {
    BYTE(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[Byte]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_BYTE, normalized, stride, data_pointer)
      })
    }
    UNSIGNED_BYTE(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[Byte]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_UNSIGNED_BYTE, normalized, stride, data_pointer)
      })
    }
    SHORT(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[Int16]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_SHORT, normalized, stride, data_pointer)
      })
    }
    UNSIGNED_SHORT(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[UInt16]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_UNSIGNED_SHORT, normalized, stride, data_pointer)
      })
    }
    INT(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[Int]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_INT, normalized, stride, data_pointer)
      })
    }
    UNSIGNED_INT(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[UInt]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_UNSIGNED_INT, normalized, stride, data_pointer)
      })
    }
    FLOAT(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[Float]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_FLOAT, normalized, stride, data_pointer)
      })
    }
    DOUBLE(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[Double]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_DOUBLE, normalized, stride, data_pointer)
      })
    }
    HALF_FLOAT(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[UInt16]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_HALF_FLOAT, normalized, stride, data_pointer)
      })
    }
    FIXED(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[Int]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_FIXED, normalized, stride, data_pointer)
      })
    }
    UNSIGNED_INT_2_10_10_10_REV(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[UInt]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(
          index,
          size,
          GL_UNSIGNED_INT_2_10_10_10_REV,
          normalized,
          stride,
          data_pointer,
        )
      })
    }
    UNSIGNED_INT_2_10_10_10_REV_EXT(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[UInt]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(
          index,
          size,
          GL_UNSIGNED_INT_2_10_10_10_REV_EXT,
          normalized,
          stride,
          data_pointer,
        )
      })
    }
    UNSIGNED_INT_10F_11F_11F_REV(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[UInt]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(
          index,
          size,
          GL_UNSIGNED_INT_10F_11F_11F_REV,
          normalized,
          stride,
          data_pointer,
        )
      })
    }
    INT_2_10_10_10_REV(data) => {
      let fp : FuncRef[(UInt, Int, UInt, Bool, Int, @c.Pointer[Int]) -> Unit] = address.unsafe_into()
      @c.borrow_array(data, fn(data_pointer) {
        fp(index, size, GL_INT_2_10_10_10_REV, normalized, stride, data_pointer)
      })
    }
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
    d_glVertexAttribPointer, index, size, normalized, stride, pointer,
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
    d_glVertexAttribPointerARB, index, size, normalized, stride, pointer,
  )
}
