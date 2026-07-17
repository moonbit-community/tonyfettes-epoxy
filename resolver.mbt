///|
/// The cross-platform GL function resolver and the self-patching dispatch slot.
///
/// Platform details (dlopen/dlsym, LoadLibrary/GetProcAddress, GLX/WGL/EGL
/// fallback chains) are entirely encapsulated in `epoxy.c` behind a single
/// entry point: `epoxy_get_proc_address(name) → void*`.
///
/// A resolved address crosses the FFI as package-private `Pointer[Unit]` — an opaque
/// `void *`. The generated wrappers reinterpret a slot's address into a
/// `FuncRef` typed to the GL function's exact ABI and call it directly, so this
/// file knows nothing about individual signatures.

///|
/// Resolve a GL entry point by name.  Returns a null pointer if the symbol is
/// simply absent (the caller — the dispatch slot — tries aliases in turn and
/// aborts only if none resolve).  Library loading and threading are handled
/// inside the C stub.
#borrow(name)
extern "c" fn epoxy_get_proc_address(name : Bytes) -> Pointer[Unit] = "epoxy_get_proc_address"

///|
extern "c" fn epoxy_cstr_to_bytes(s : Pointer[Byte]) -> Bytes = "epoxy_cstr_to_bytes"

///|
/// Look up a single symbol, returning a null pointer if it is simply absent.
/// (MoonBit-allocated `Bytes` always carry a trailing NUL, so the UTF-8
/// encoding is already a valid C string — no terminator to add.)
fn lookup_symbol(name : String) -> Pointer[Unit] {
  epoxy_get_proc_address(@utf8.encode(name))
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
  mut ptr : Pointer[Unit]
}

///|
fn Dispatch::new(name : String) -> Dispatch {
  { name, aliases: [], ptr: Pointer::null() }
}

///|
fn Dispatch::with_aliases(name : String, aliases : Array[String]) -> Dispatch {
  { name, aliases, ptr: Pointer::null() }
}

///|
/// Return the resolved address, resolving (and caching) on first call. Tries
/// the primary name then each alias; aborts only if none of them resolve.
fn Dispatch::get(self : Dispatch) -> Pointer[Unit] {
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
