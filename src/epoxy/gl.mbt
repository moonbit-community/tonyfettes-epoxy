///|
/// GL enum constants used by the demo (from gl.xml <enums>). The entry points
/// themselves (glGetString, glClear, ...) live in the generated
/// `gl_generated.mbt`.
pub const GL_NO_ERROR : UInt = 0x0000

///|
pub const GL_VENDOR : UInt = 0x1F00

///|
pub const GL_RENDERER : UInt = 0x1F01

///|
pub const GL_VERSION : UInt = 0x1F02

///|
pub const GL_EXTENSIONS : UInt = 0x1F03

///|
/// Number of extensions, queryable via `glGetIntegerv` on GL 3.0+.
pub const GL_NUM_EXTENSIONS : UInt = 0x821D

///|
/// `glCreateShader` stage selector (the demo compiles a vertex shader).
pub const GL_VERTEX_SHADER : UInt = 0x8B31

///|
/// `glGetShaderiv` query: 1 once the shader compiled without error.
pub const GL_COMPILE_STATUS : UInt = 0x8B81

///|
/// The fixed-function current color, set by `glColor*` and read by `glGetFloatv`
/// (the demo uses it to round-trip a 16-bit array).
pub const GL_CURRENT_COLOR : UInt = 0x0B00
