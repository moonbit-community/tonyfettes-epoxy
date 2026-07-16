// C stubs for the MoonBit epoxy library: platform GL function dispatch.
//
// Entry points are resolved at runtime without linking any GL library:
//   - macOS:   dlopen(OpenGL.framework)  + dlsym
//   - Linux:   dlopen(libOpenGL/libGL)   + dlsym → glXGetProcAddress fallback
//   - Windows: LoadLibrary(opengl32.dll) + GetProcAddress → wglGetProcAddress
//
// MoonBit sees exactly one function: epoxy_get_proc_address(name) → void*.
// The generated wrappers reinterpret the returned pointer into a FuncRef
// typed to the target GL function's exact ABI and call it directly.

#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#include "moonbit.h"

#if defined(_WIN32)
  #include <windows.h>
#else
  #include <dlfcn.h>
  #include <pthread.h>
#endif

// ── Platform library paths ────────────────────────────────────────────────

#if defined(__APPLE__)
  #define GL_LIB_PATH "/System/Library/Frameworks/OpenGL.framework/OpenGL"
#elif defined(_WIN32)
  #define GL_LIB_PATH "opengl32.dll"
#else
  // glvnd (modern Linux): libOpenGL.so.0 + libGLX.so.1
  // classic:              libGL.so.1 (provides both GL and GLX symbols)
  #define GLVND_GL_LIB   "libOpenGL.so.0"
  #define GLVND_GLX_LIB  "libGLX.so.1"
  #define CLASSIC_GL_LIB "libGL.so.1"
#endif

// ── State ─────────────────────────────────────────────────────────────────

#if defined(_WIN32)

  static HMODULE gl_module = NULL;

  typedef void (WINAPI *GLfunction)(void);
  typedef GLfunction (WINAPI *wglGetProcAddress_t)(LPCSTR);
  static wglGetProcAddress_t wglGPA = NULL;

  static CRITICAL_SECTION epoxy_lock;
  static BOOL            epoxy_lock_inited = FALSE;

#else

  static void *gl_handle = NULL;

  #if !defined(__APPLE__)
    static void *glx_handle = NULL;
    typedef void (*GLfunction)(void);
    typedef GLfunction (*glXGetProcAddress_t)(const unsigned char *);
    static glXGetProcAddress_t glXGPA = NULL;
  #endif

  static pthread_mutex_t epoxy_mutex = PTHREAD_MUTEX_INITIALIZER;

#endif

// ── Locking helpers ───────────────────────────────────────────────────────

#if defined(_WIN32)

static void epoxy_lock_acquire(void) {
  if (!epoxy_lock_inited) {
    InitializeCriticalSection(&epoxy_lock);
    epoxy_lock_inited = TRUE;
  }
  EnterCriticalSection(&epoxy_lock);
}

static void epoxy_lock_release(void) {
  LeaveCriticalSection(&epoxy_lock);
}

#else

static void epoxy_lock_acquire(void) {
  pthread_mutex_lock(&epoxy_mutex);
}

static void epoxy_lock_release(void) {
  pthread_mutex_unlock(&epoxy_mutex);
}

#endif

// ── One-time library loading ──────────────────────────────────────────────

#if defined(__APPLE__)

static void open_and_init(void) {
  if (gl_handle) return;

  epoxy_lock_acquire();
  if (gl_handle) { epoxy_lock_release(); return; }

  gl_handle = dlopen(GL_LIB_PATH, RTLD_LAZY | RTLD_GLOBAL);
  if (!gl_handle) {
    fprintf(stderr, "epoxy: could not open %s\n", GL_LIB_PATH);
    abort();
  }

  epoxy_lock_release();
}

#elif defined(_WIN32)

static void open_and_init(void) {
  if (gl_module) return;

  epoxy_lock_acquire();
  if (gl_module) { epoxy_lock_release(); return; }

  gl_module = LoadLibraryA(GL_LIB_PATH);
  if (!gl_module) {
    fprintf(stderr, "epoxy: could not open %s\n", GL_LIB_PATH);
    abort();
  }

  // Pre-resolve wglGetProcAddress for the extension-fallback path.
  wglGPA = (wglGetProcAddress_t)GetProcAddress(gl_module, "wglGetProcAddress");

  epoxy_lock_release();
}

#else  // Linux

static void open_and_init(void) {
  if (gl_handle) return;

  epoxy_lock_acquire();
  if (gl_handle) { epoxy_lock_release(); return; }

  // Prefer glvnd libOpenGL, fall back to classic libGL.
  gl_handle = dlopen(GLVND_GL_LIB, RTLD_LAZY | RTLD_LOCAL);
  if (!gl_handle) {
    gl_handle = dlopen(CLASSIC_GL_LIB, RTLD_LAZY | RTLD_LOCAL);
  }
  if (!gl_handle) {
    fprintf(stderr, "epoxy: could not open %s or %s\n",
            GLVND_GL_LIB, CLASSIC_GL_LIB);
    abort();
  }

  // Try to open the GLX library for glXGetProcAddress fallback.
  // On glvnd, GLX is a separate library; on classic, GLX symbols live
  // in libGL itself, so just reuse gl_handle.
  glx_handle = dlopen(GLVND_GLX_LIB, RTLD_LAZY | RTLD_LOCAL);
  if (!glx_handle) {
    glx_handle = gl_handle;
  }

  // glXGetProcAddressARB is the standard name; some implementations only
  // export glXGetProcAddress.
  glXGPA = (glXGetProcAddress_t)dlsym(glx_handle, "glXGetProcAddressARB");
  if (!glXGPA) {
    glXGPA = (glXGetProcAddress_t)dlsym(glx_handle, "glXGetProcAddress");
  }

  epoxy_lock_release();
}

#endif

// ── Public entry point ────────────────────────────────────────────────────

// Resolve a GL entry point by NUL-terminated name.  Returns NULL if the
// symbol is not found (callers — the Dispatch slot — try aliases in turn
// and abort only if none of them resolve).

void *epoxy_get_proc_address(moonbit_bytes_t name) {
  open_and_init();

  const char *cname = (const char *)name;
  void       *result = NULL;

#if defined(__APPLE__)
  result = dlsym(gl_handle, cname);

#elif defined(_WIN32)
  result = GetProcAddress(gl_module, cname);
  if (!result && wglGPA) {
    result = (void *)wglGPA(cname);
  }

#else  // Linux
  result = dlsym(gl_handle, cname);
  if (!result && glXGPA) {
    result = (void *)glXGPA((const unsigned char *)cname);
  }

#endif

  return result;
}

// ── String conversion ─────────────────────────────────────────────────────

// Convert a NUL-terminated C string (e.g. glGetString's return) into a
// MoonBit-owned Bytes.  A NULL pointer yields an empty Bytes.

moonbit_bytes_t epoxy_cstr_to_bytes(const char *s) {
  if (!s) {
    return moonbit_make_bytes_raw(0);
  }
  int32_t len = (int32_t)strlen(s);
  moonbit_bytes_t bytes = moonbit_make_bytes_raw(len);
  memcpy(bytes, s, len);
  return bytes;
}
