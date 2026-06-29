///|
/// Hand-written support shared by the generated bindings: GL enum constants,
/// the UTF-8 decoder used by string-returning entry points, and the demo
/// offscreen-context helper. The entry points themselves (glGetString,
/// glClear, ...) live in the generated `gl_generated.mbt`.

///|
/// GL enum constants used by the demo (from gl.xml <enums>).
pub const GL_NO_ERROR : UInt = 0x0000

///|
pub const GL_VENDOR : UInt = 0x1F00

///|
pub const GL_RENDERER : UInt = 0x1F01

///|
pub const GL_VERSION : UInt = 0x1F02

///|
/// Decode a GL-returned byte buffer into a MoonBit String. Shared by every
/// generated string-returning entry point.
fn decode_utf8(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes[:])
}

///|
/// Demo helper: create+make-current an offscreen GL context so the entry
/// points have something to talk to. Real apps supply their own context.
extern "c" fn ffi_demo_make_context() -> Int = "epoxy_demo_make_context"

///|
pub fn demo_make_context() -> Bool {
  ffi_demo_make_context() == 1
}
