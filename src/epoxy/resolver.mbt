///|
/// An opaque C pointer: a dlopen handle or a resolved entry-point address.
#external
type CPtr

///|
extern "c" fn ffi_gl_dlopen() -> CPtr = "epoxy_gl_dlopen"

///|
#borrow(name)
extern "c" fn ffi_dlsym(handle : CPtr, name : Bytes) -> CPtr = "epoxy_dlsym"

///|
extern "c" fn ffi_ptr_is_null(p : CPtr) -> Bool = "epoxy_ptr_is_null"

///|
/// Lazily-opened handle to the platform GL library, opened once (epoxy opens
/// libGL / OpenGL.framework on first use and keeps it for the process).
let gl_handle : Ref[CPtr?] = { val: None }

///|
pub suberror ResolveError String

///|
pub impl Show for ResolveError with output(self, logger) {
  let ResolveError(msg) = self
  logger.write_string("ResolveError(" + msg + ")")
}

///|
/// Get the GL library handle, dlopen-ing it on first call.
fn gl_lib() -> CPtr raise ResolveError {
  match gl_handle.val {
    Some(h) => h
    None => {
      let h = ffi_gl_dlopen()
      if ffi_ptr_is_null(h) {
        raise ResolveError("failed to dlopen the GL library")
      }
      gl_handle.val = Some(h)
      h
    }
  }
}

///|
/// Convert a MoonBit string to a NUL-terminated C string buffer.
fn cstr(s : String) -> Bytes {
  let b : Array[Byte] = []
  for c in s {
    // entry-point names are ASCII, so one byte per char is exact.
    b.push((c.to_int() & 0xff).to_byte())
  }
  b.push((0).to_byte())
  Bytes::from_array(b)
}

///|
/// Resolve a single entry point by name. Raises if the symbol is absent.
fn resolve(name : String) -> CPtr raise ResolveError {
  let p = ffi_dlsym(gl_lib(), cstr(name))
  if ffi_ptr_is_null(p) {
    raise ResolveError("entry point not found: " + name)
  }
  p
}

///|
/// A self-patching dispatch slot, the MoonBit analogue of epoxy's global
/// rewrite pointer: it resolves the entry point on first use and caches it.
priv struct Dispatch {
  name : String
  ptr : Ref[CPtr?]
}

///|
fn Dispatch::new(name : String) -> Dispatch {
  { name, ptr: { val: None } }
}

///|
/// Return the resolved address, resolving (and caching) on first call.
fn Dispatch::get(self : Dispatch) -> CPtr raise ResolveError {
  match self.ptr.val {
    Some(p) => p
    None => {
      let p = resolve(self.name)
      self.ptr.val = Some(p)
      p
    }
  }
}
