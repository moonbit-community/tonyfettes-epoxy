// C stubs for the MoonBit epoxy slice.
//
// Two distinct responsibilities, mirroring libepoxy's design:
//   1. GL *function dispatch* — resolve GL entry points dynamically with
//      dlopen()/dlsym(), exactly like epoxy. The rest of the library never
//      link-depends on individual GL functions.
//   2. Per-signature call shims — a tiny `extern "C"` wrapper per distinct GL
//      function signature, casting the resolved void* to the right function
//      pointer type and marshalling values to/from MoonBit runtime types.
//
// The offscreen-context helper is NOT part of epoxy proper; it stands in for
// "the application/toolkit created a GL context", which is a window-system
// concern (CGL/EGL/GLX/WGL) layered on top of dispatch.

#define GL_SILENCE_DEPRECATION 1

#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include "moonbit.h"

#ifdef __APPLE__
#include <OpenGL/OpenGL.h>
#define GL_LIB_PATH "/System/Library/Frameworks/OpenGL.framework/OpenGL"
#else
#define GL_LIB_PATH "libGL.so.1"
#endif

typedef unsigned int GLenum;
typedef unsigned char GLubyte;

// --- 1. Dynamic resolver -------------------------------------------------

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

// Per-signature call shims live in the generated gl_generated_stub.c.

// --- demo only: offscreen GL context (window-system layer stand-in) -----

#ifdef __APPLE__
int epoxy_demo_make_context(void) {
  CGLPixelFormatAttribute attribs[] = { (CGLPixelFormatAttribute)0 };
  CGLPixelFormatObj pix;
  GLint npix;
  if (CGLChoosePixelFormat(attribs, &pix, &npix) != kCGLNoError) return 0;
  CGLContextObj ctx;
  CGLError err = CGLCreateContext(pix, NULL, &ctx);
  CGLDestroyPixelFormat(pix);
  if (err != kCGLNoError) return 0;
  return CGLSetCurrentContext(ctx) == kCGLNoError ? 1 : 0;
}
#else
int epoxy_demo_make_context(void) { return 0; }
#endif
