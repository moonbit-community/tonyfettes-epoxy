///|
/// Window-system layer (the app's job, not epoxy's): open a window with a
/// current GL context and pump its events. Implemented in demo_window.m; the
/// only reason this demo links Cocoa/OpenGL.
extern "c" fn ffi_window_open(width : Int, height : Int) -> Int = "demo_window_open"

///|
/// Present the just-drawn frame and process events; 0 once the window closes.
extern "c" fn ffi_window_frame() -> Int = "demo_window_frame"

///|
const WIDTH : Int = 640

///|
const HEIGHT : Int = 480

///|
/// Compile one shader, printing the driver's info log on failure.
fn compile_shader(kind : UInt, source : Bytes) -> UInt? {
  let shader = @epoxy.gl_create_shader(kind)
  let sources : FixedArray[Bytes] = [source]
  let lengths : FixedArray[Int] = [source.length()]
  @epoxy.gl_shader_source(shader, 1, sources, lengths)
  @epoxy.gl_compile_shader(shader)
  let status : FixedArray[Int] = FixedArray::make(1, 0)
  @epoxy.gl_get_shaderiv(shader, @epoxy.GL_COMPILE_STATUS, status)
  if status[0] == 1 {
    Some(shader)
  } else {
    let log = Bytes::make(1024, 0)
    let log_len : FixedArray[Int] = FixedArray::make(1, 0)
    @epoxy.gl_get_shader_info_log(shader, log.length(), log_len, log)
    println("shader compile failed: \{@utf8.decode_lossy(log[0:log_len[0]])}")
    None
  }
}

///|
/// The RGB triangle's base shape, rotated by `angle` around the origin.
/// Aspect-corrected so it stays equilateral in a non-square window.
fn triangle_positions(angle : Float) -> FixedArray[Float] {
  let base : Array[(Float, Float)] = [(-0.6, -0.5), (0.6, -0.5), (0.0, 0.7)]
  let aspect = Float::from_int(WIDTH) / Float::from_int(HEIGHT)
  let (s, c) = (@math.sinf(angle), @math.cosf(angle))
  let out : Array[Float] = []
  for p in base {
    let (x, y) = p
    out.push((x * c - y * s) / aspect)
    out.push(x * s + y * c)
  }
  FixedArray::from_array(out)
}

///|
fn main {
  guard ffi_window_open(WIDTH, HEIGHT) == 1 else {
    println("could not open a GL window (macOS only demo)")
    return
  }

  // Same GLSL 1.20 pair as examples/triangle: pass position through,
  // interpolate a per-vertex color across the triangle.
  let vs_src : Bytes = b"#version 120\nattribute vec2 pos;\nattribute vec3 color;\nvarying vec3 v_color;\nvoid main() { v_color = color; gl_Position = vec4(pos, 0.0, 1.0); }\n"
  let fs_src : Bytes = b"#version 120\nvarying vec3 v_color;\nvoid main() { gl_FragColor = vec4(v_color, 1.0); }\n"
  guard compile_shader(@epoxy.GL_VERTEX_SHADER, vs_src) is Some(vs) else {
    return
  }
  guard compile_shader(@epoxy.GL_FRAGMENT_SHADER, fs_src) is Some(fs) else {
    return
  }
  let program = @epoxy.gl_create_program()
  @epoxy.gl_attach_shader(program, vs)
  @epoxy.gl_attach_shader(program, fs)
  @epoxy.gl_link_program(program)
  let linked : FixedArray[Int] = FixedArray::make(1, 0)
  @epoxy.gl_get_programiv(program, @epoxy.GL_LINK_STATUS, linked)
  guard linked[0] == 1 else {
    println("program link failed")
    return
  }
  @epoxy.gl_use_program(program)
  let pos_loc = @epoxy.gl_get_attrib_location(program, b"pos")
  let color_loc = @epoxy.gl_get_attrib_location(program, b"color")
  guard pos_loc >= 0 && color_loc >= 0 else {
    println("attribute location not found")
    return
  }
  let pos_loc = pos_loc.reinterpret_as_uint()
  let color_loc = color_loc.reinterpret_as_uint()
  @epoxy.gl_enable_vertex_attrib_array(pos_loc)
  @epoxy.gl_enable_vertex_attrib_array(color_loc)

  let buffers : FixedArray[UInt] = FixedArray::make(2, 0)
  @epoxy.gl_gen_buffers(2, buffers)
  let position_buffer = buffers[0]
  let color_buffer = buffers[1]

  // The static color array is copied into its VBO and can be released as soon
  // as gl_buffer_data returns. gl_vertex_attrib_pointer stores only a buffer
  // association and byte offset, never a pointer into MoonBit memory.
  let colors : FixedArray[Float] = [
    1.0, 0.0, 0.0, // red
     0.0, 1.0, 0.0, // green
     0.0, 0.0, 1.0, // blue
  ]
  @epoxy.gl_bind_buffer(@epoxy.GL_ARRAY_BUFFER, color_buffer)
  @epoxy.gl_buffer_data(@epoxy.GL_ARRAY_BUFFER, colors, @epoxy.GL_STATIC_DRAW)
  @epoxy.gl_vertex_attrib_pointer(color_loc, 3, @epoxy.GL_FLOAT, false, 0, 0L)

  // Reserve six Float values once; each frame updates that storage in place.
  @epoxy.gl_bind_buffer(@epoxy.GL_ARRAY_BUFFER, position_buffer)
  @epoxy.gl_buffer_allocate(
    @epoxy.GL_ARRAY_BUFFER,
    6L * 4L,
    @epoxy.GL_STREAM_DRAW,
  )
  @epoxy.gl_vertex_attrib_pointer(pos_loc, 2, @epoxy.GL_FLOAT, false, 0, 0L)
  @epoxy.gl_viewport(0, 0, WIDTH, HEIGHT)
  @epoxy.gl_clear_color(0.1, 0.1, 0.1, 1.0)

  println("window open — close it to quit")
  let mut angle : Float = 0.0
  for ;; {
    let positions = triangle_positions(angle)
    @epoxy.gl_bind_buffer(@epoxy.GL_ARRAY_BUFFER, position_buffer)
    @epoxy.gl_buffer_sub_data(@epoxy.GL_ARRAY_BUFFER, 0L, positions)
    @epoxy.gl_clear(@epoxy.GL_COLOR_BUFFER_BIT)
    @epoxy.gl_draw_arrays(@epoxy.GL_TRIANGLES, 0, 3)
    let alive = ffi_window_frame()
    guard alive == 1 else { break }
    angle += 0.02
  }
  @epoxy.gl_delete_buffers(2, buffers)
  println("window closed")
}
