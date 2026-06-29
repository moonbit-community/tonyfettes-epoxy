// Demo-only: create an offscreen GL context so the demo's GL calls have
// something current to talk to. This is the window-system layer's job
// (CGL/EGL/GLX/WGL) — NOT epoxy's — so it lives in the demo, not the library.
// It is the sole reason the demo links against the OpenGL framework; epoxy
// itself only dlopen()s.

#define GL_SILENCE_DEPRECATION 1

#include <stddef.h>
#include <stdint.h>

#ifdef __APPLE__
#include <OpenGL/OpenGL.h>

int demo_make_context(void) {
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
int demo_make_context(void) { return 0; }
#endif
