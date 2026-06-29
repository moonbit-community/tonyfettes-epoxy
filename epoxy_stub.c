// C stubs for the MoonBit epoxy library: purely GL *function dispatch*.
// Entry points are resolved dynamically with dlopen()/dlsym() (exactly like
// libepoxy), so the library never link-depends on GL — no -lGL / -framework
// OpenGL here, only -ldl. Per-signature call shims live in the generated
// gl_generated_stub.c.

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

// A null CPtr, used as the unresolved sentinel on the MoonBit side.
void *epoxy_null(void) { return NULL; }

// NULL check, so MoonBit can detect failed dlopen/dlsym across the #external
// boundary (it can't compare an opaque pointer to null directly).
int epoxy_ptr_is_null(void *p) { return p == NULL; }
