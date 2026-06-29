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
  } catch {
    e => println("dispatch failed: \{e}")
  }
}
