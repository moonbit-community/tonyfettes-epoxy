// C stubs for the MoonBit epoxy library: purely GL *function dispatch*.
// Entry points are resolved dynamically with dlopen()/dlsym() (exactly like
// libepoxy), so the library never link-depends on GL — no -lGL / -framework
// OpenGL here, only -ldl. There are no per-command call shims: the generated
// wrappers call each resolved address directly through a MoonBit FuncRef. The
// only marshalling helper left here is epoxy_cstr(), shared by every
// string-returning command.

#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include "moonbit.h"

#ifdef __APPLE__
#define GL_LIB_PATH "/System/Library/Frameworks/OpenGL.framework/OpenGL"
#else
#define GL_LIB_PATH "libGL.so.1"
#endif

// --- Dynamic resolver ----------------------------------------------------

// dlopen the platform GL library. Returns an opaque handle (void*), NULL on
// failure. This is epoxy_*_dlopen()'s job.
void *epoxy_gl_dlopen(void) {
  return dlopen(GL_LIB_PATH, RTLD_LAZY | RTLD_GLOBAL);
}

// Resolve one entry point by NUL-terminated name. This is do_dlsym().
void *epoxy_dlsym(void *handle, moonbit_bytes_t name) {
  if (!handle) return NULL;
  return dlsym(handle, (const char *)name);
}

// Marshal a NUL-terminated C string (e.g. glGetString's return) into MoonBit
// bytes; a NULL pointer yields empty. One generic helper for every
// string-returning command, not a per-command shim.
moonbit_bytes_t epoxy_cstr(const unsigned char *s) {
  if (!s) return moonbit_make_bytes(0, 0);
  size_t len = strlen((const char *)s);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  memcpy(out, s, len);
  return out;
}
