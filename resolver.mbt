///|
/// The lazy dlopen/dlsym resolver and the self-patching dispatch slot.
///
/// A resolved address crosses the FFI as `@c.Pointer[Unit]` — an opaque
/// `void *`. The generated wrappers reinterpret a slot's address into a
/// `FuncRef` typed to the GL function's exact ABI and call it directly, so this
/// file knows nothing about individual signatures.

///|
extern "c" fn epoxy_gl_dlopen() -> @c.Pointer[Unit] = "epoxy_gl_dlopen"

///|
#borrow(name)
extern "c" fn epoxy_dlsym(
  handle : @c.Pointer[Unit],
  name : Bytes,
) -> @c.Pointer[Unit] = "epoxy_dlsym"

///|
/// Marshal a NUL-terminated C string into MoonBit `Bytes` (NULL → empty). One
/// generic helper shared by every string-returning command's wrapper.
#borrow(s)
extern "c" fn epoxy_cstr(s : @c.Pointer[Byte]) -> Bytes = "epoxy_cstr"

///|
/// Lazily-opened handle to the platform GL library, opened once (epoxy opens
/// libGL / OpenGL.framework on first use and keeps it for the process).
let gl_handle : Ref[@c.Pointer[Unit]] = { val: @c.Pointer::null() }

///|
/// Get the GL library handle, dlopen-ing it on first call. Aborts if the
/// platform GL library cannot be opened at all — mirroring libepoxy, whose
/// dispatch likewise `abort()`s rather than threading an error through every
/// call (`dispatch_common.c`: `Couldn't open ...` / `abort()`).
fn gl_lib() -> @c.Pointer[Unit] {
  if gl_handle.val.is_null() {
    let h = epoxy_gl_dlopen()
    if h.is_null() {
      abort("epoxy: could not load the platform GL library")
    }
    gl_handle.val = h
  }
  gl_handle.val
}

///|
/// Look up a single symbol, returning a null pointer if it is simply absent.
/// (MoonBit-allocated `Bytes` always carry a trailing NUL, so the UTF-8
/// encoding is already a valid C string for `dlsym` — no terminator to add.)
fn lookup_symbol(name : String) -> @c.Pointer[Unit] {
  epoxy_dlsym(gl_lib(), @utf8.encode(name))
}

///|
/// A self-patching dispatch slot, the MoonBit analogue of epoxy's global
/// rewrite pointer: it resolves the entry point on first use and caches it.
/// `ptr` starts null and is patched in place on first `get`.
///
/// A GL function often has several names — it first ships as an extension
/// (`...OES`, `...APPLE`) and later enters core — and a given driver may export
/// only some of them. `aliases` holds the fallback names (the registry's alias
/// group, minus `name`); `get` tries `name` first, then each alias, so a core
/// call still resolves on a driver that only exports an extension form. If none
/// resolve, `get` aborts — calling an entry point the context doesn't provide
/// is a programming error (gate it on `gl_version`/`has_gl_extension` first).
priv struct Dispatch {
  name : String // primary entry point, also used in the not-found error
  aliases : Array[String] // fallback names, tried in order after `name`
  mut ptr : @c.Pointer[Unit]
}

///|
fn Dispatch::new(name : String) -> Dispatch {
  { name, aliases: [], ptr: @c.Pointer::null() }
}

///|
fn Dispatch::with_aliases(name : String, aliases : Array[String]) -> Dispatch {
  { name, aliases, ptr: @c.Pointer::null() }
}

///|
/// Return the resolved address, resolving (and caching) on first call. Tries
/// the primary name then each alias; aborts only if none of them resolve.
fn Dispatch::get(self : Dispatch) -> @c.Pointer[Unit] {
  if self.ptr.is_null() {
    let mut found = lookup_symbol(self.name)
    for candidate in self.aliases {
      if !found.is_null() {
        break
      }
      found = lookup_symbol(candidate)
    }
    if found.is_null() {
      abort("epoxy: \{self.name}() not found")
    }
    self.ptr = found
  }
  self.ptr
}
