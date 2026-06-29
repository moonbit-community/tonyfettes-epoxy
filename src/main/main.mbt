///|
/// Window-system layer (the app's job, not epoxy's): make a current GL context.
/// Implemented in demo_context.c; the only reason this demo links OpenGL.
extern "c" fn ffi_make_context() -> Int = "demo_make_context"

///|
fn main {
  guard ffi_make_context() == 1 else {
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

    // Introspection API: version/extension detection, epoxy-style.
    let version = @epoxy.gl_version()
    println("gl_version  = \{version} (\{version / 10}.\{version % 10})")
    println("is_desktop  = \{@epoxy.is_desktop_gl()}")
    let probe = "GL_APPLE_vertex_array_object"
    println("has \{probe} = \{@epoxy.has_gl_extension(probe)}")

    // Exercise generated pointer bindings end-to-end.
    // glGetIntegerv writes into a FixedArray[Int] output buffer.
    let max_tex : FixedArray[Int] = FixedArray::make(1, 0)
    @epoxy.gl_get_integerv(0x0D33, max_tex) // GL_MAX_TEXTURE_SIZE
    println("GL_MAX_TEXTURE_SIZE = \{max_tex[0]}")
    // glGenBuffers fills a FixedArray[UInt] with fresh object names.
    let bufs : FixedArray[UInt] = FixedArray::make(3, 0)
    @epoxy.gl_gen_buffers(3, bufs)
    println("glGenBuffers -> [\{bufs[0]}, \{bufs[1]}, \{bufs[2]}]")

    // glShaderSource is the `const GLchar *const *` shape: a FixedArray[Bytes]
    // crosses as the `char **` GL wants, with an explicit length array so the
    // (non-NUL-terminated) MoonBit bytes are read exactly. Compile a trivial
    // GLSL 1.20 vertex shader to prove the whole path end-to-end.
    let source : Bytes = b"#version 120\nvoid main() { gl_Position = vec4(0.0); }\n"
    let sources : FixedArray[Bytes] = [source]
    let lengths : FixedArray[Int] = [source.length()]
    let shader = @epoxy.gl_create_shader(@epoxy.GL_VERTEX_SHADER)
    @epoxy.gl_shader_source(shader, 1, sources, lengths)
    @epoxy.gl_compile_shader(shader)
    let status : FixedArray[Int] = FixedArray::make(1, 0)
    @epoxy.gl_get_shaderiv(shader, @epoxy.GL_COMPILE_STATUS, status)
    println("glShaderSource+compile ok = \{status[0] == 1}")
  } catch {
    e => println("dispatch failed: \{e}")
  }
}
