// C stubs for the MoonBit epoxy library: purely GL *function dispatch*.
// Entry points are resolved dynamically with dlopen()/dlsym() (exactly like
// libepoxy), so the library never link-depends on GL — no -lGL / -framework
// OpenGL here, only -ldl. There are no call shims at all: the generated
// wrappers call each resolved address directly through a MoonBit FuncRef, and
// C-string returns are walked MoonBit-side (epoxy_cstr in resolver.mbt). This
// file is now just the dlopen/dlsym resolver.

#include <dlfcn.h>
#include <stddef.h>
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
