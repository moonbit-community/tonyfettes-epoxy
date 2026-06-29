///|
/// Opaque GL object handles: pointer-valued tokens you receive from a GL call
/// and hand straight back to another, never constructing or inspecting them.
///
/// Each is its own nominal `#external` type — a bare pointer at the FFI
/// boundary — so a sync object cannot be passed where an EGL image is expected.
/// They are produced and consumed only by the generated bindings (`gl_fence_sync`
/// returns a `GLsync`, `gl_wait_sync` takes one, and so on).

///|
/// A sync object (`GLsync`), from `glFenceSync` / `glWaitSync` & co.
#external
pub type GLsync

///|
/// An `EGLImage` imported into GL (`GLeglImageOES`).
#external
pub type GLeglImageOES

///|
/// An EGL client buffer (`GLeglClientBufferEXT`), e.g. for external storage.
#external
pub type GLeglClientBufferEXT

///|
/// A Vulkan entry-point address returned by `glGetVkProcAddrNV`
/// (`GLVULKANPROCNV`).
#external
pub type GLVULKANPROCNV
