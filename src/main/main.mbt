///|
fn main {
  // The application/toolkit creates a GL context (window-system layer).
  guard @epoxy.demo_make_context() else {
    println("could not create an offscreen GL context")
    return
  }

  // From here on, every GL call is resolved on first use via dlopen/dlsym,
  // then cached — the app just calls undecorated names, epoxy-style.
  try {
    println("GL_VERSION  = " + @epoxy.gl_get_string(@epoxy.GL_VERSION))
    println("GL_VENDOR   = " + @epoxy.gl_get_string(@epoxy.GL_VENDOR))
    println("GL_RENDERER = " + @epoxy.gl_get_string(@epoxy.GL_RENDERER))
    let err = @epoxy.gl_get_error()
    println("glGetError  = \{err} (GL_NO_ERROR=\{@epoxy.GL_NO_ERROR})")

    // Exercise generated pointer bindings end-to-end.
    // glGetIntegerv writes into a FixedArray[Int] output buffer.
    let max_tex : FixedArray[Int] = FixedArray::make(1, 0)
    @epoxy.gl_get_integerv(0x0D33, max_tex) // GL_MAX_TEXTURE_SIZE
    println("GL_MAX_TEXTURE_SIZE = \{max_tex[0]}")
    // glGenBuffers fills a FixedArray[UInt] with fresh object names.
    let bufs : FixedArray[UInt] = FixedArray::make(3, 0)
    @epoxy.gl_gen_buffers(3, bufs)
    println("glGenBuffers -> [\{bufs[0]}, \{bufs[1]}, \{bufs[2]}]")
  } catch {
    e => println("dispatch failed: \{e}")
  }
}
