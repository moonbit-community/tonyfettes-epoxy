///|
/// An opaque C pointer: a dlopen handle or a resolved entry-point address.
/// It is nullable by nature, so `is_null` is the unresolved/failed sentinel —
/// no extra `Option` wrapper is needed.
#external
priv type CPtr

///|
extern "c" fn CPtr::null() -> CPtr = "epoxy_null"

///|
extern "c" fn CPtr::is_null(self : CPtr) -> Bool = "epoxy_ptr_is_null"

///|
extern "c" fn epoxy_gl_dlopen() -> CPtr = "epoxy_gl_dlopen"

///|
#borrow(name)
extern "c" fn epoxy_dlsym(handle : CPtr, name : Bytes) -> CPtr = "epoxy_dlsym"

///|
/// Lazily-opened handle to the platform GL library, opened once (epoxy opens
/// libGL / OpenGL.framework on first use and keeps it for the process).
let gl_handle : Ref[CPtr] = { val: CPtr::null() }

///|
pub suberror ResolveError {
  ResolveError(String)
}

///|
pub impl Show for ResolveError with output(self, logger) {
  let ResolveError(msg) = self
  logger.write_string("ResolveError(" + msg + ")")
}

///|
/// Get the GL library handle, dlopen-ing it on first call.
fn gl_lib() -> CPtr raise ResolveError {
  if gl_handle.val.is_null() {
    let h = epoxy_gl_dlopen()
    if h.is_null() {
      raise ResolveError("failed to dlopen the GL library")
    }
    gl_handle.val = h
  }
  gl_handle.val
}

///|
/// Resolve a single entry point by name. Raises if the symbol is absent.
/// (MoonBit-allocated `Bytes` always carry a trailing NUL, so the UTF-8
/// encoding is already a valid C string for `dlsym` — no terminator to add.)
fn resolve(name : String) -> CPtr raise ResolveError {
  let p = epoxy_dlsym(gl_lib(), @utf8.encode(name))
  if p.is_null() {
    raise ResolveError("entry point not found: " + name)
  }
  p
}

///|
/// A self-patching dispatch slot, the MoonBit analogue of epoxy's global
/// rewrite pointer: it resolves the entry point on first use and caches it.
/// `ptr` starts null and is patched in place on first `get`.
priv struct Dispatch {
  name : String
  mut ptr : CPtr
}

///|
fn Dispatch::new(name : String) -> Dispatch {
  { name, ptr: CPtr::null() }
}

///|
/// Return the resolved address, resolving (and caching) on first call.
fn Dispatch::get(self : Dispatch) -> CPtr raise ResolveError {
  if self.ptr.is_null() {
    self.ptr = resolve(self.name)
  }
  self.ptr
}
