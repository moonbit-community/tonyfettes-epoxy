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
  // glvnd (modern Linux): libOpenGL.so.0 + libGLX.so.0
  // classic:              libGL.so.1 (provides both GL and GLX symbols)
  #define GLVND_GL_LIB   "libOpenGL.so.0"
  #define GLVND_GLX_LIB  "libGLX.so.0"
  #define CLASSIC_GL_LIB "libGL.so.1"
#endif

// ── State ─────────────────────────────────────────────────────────────────

#if defined(_WIN32)

  static HMODULE gl_module = NULL;

  typedef void (WINAPI *GLfunction)(void);
  typedef GLfunction (WINAPI *wglGetProcAddress_t)(LPCSTR);
  static wglGetProcAddress_t wglGPA = NULL;

  // Init-once for the critical section so two threads that race into their
  // first GL call cannot double-initialize (InitializeCriticalSection is
  // not itself re-entrant).  INIT_ONCE guarantees exactly-one execution
  // without manual double-checked locking on the "inited" flag.
  static INIT_ONCE       epoxy_init_once_flag = INIT_ONCE_STATIC_INIT;
  static CRITICAL_SECTION epoxy_lock;

  // Double-checked locking with a dedicated "ready" flag that is only set
  // after *every* field is initialized — gl_module and wglGPA.  On x86/x64
  // (the only Windows architectures) stores are already total-store-ordered,
  // but InterlockedExchange adds an explicit full barrier for paranoia.
  static volatile LONG   epoxy_ready = 0;

  // wglGetProcAddress signals "not found" with non‑NULL sentinel values
  // (1, 2, 3, or -1); a raw pointer test treats every sentinel as a
  // resolved function and Dispatch caches it, crashing on invocation.
  static int is_wgl_sentinel(void *p) {
    uintptr_t v = (uintptr_t)p;
    return v == 1 || v == 2 || v == 3 || v == (uintptr_t)-1;
  }

#else

  // pthread_once guarantees the init routine runs exactly once and that its
  // side effects are visible to every thread after pthread_once returns — no
  // manual double-checked locking, no memory-ordering footguns.
  static pthread_once_t  epoxy_init_once = PTHREAD_ONCE_INIT;

  static void *gl_handle = NULL;

  #if !defined(__APPLE__)
    static void *glx_handle = NULL;
    typedef void (*GLfunction)(void);
    typedef GLfunction (*glXGetProcAddress_t)(const unsigned char *);
    static glXGetProcAddress_t glXGPA = NULL;
  #endif

#endif

// ── One-time library loading ──────────────────────────────────────────────

#if defined(_WIN32)

static BOOL CALLBACK init_cs_cb(PINIT_ONCE once, PVOID param, PVOID *ctx) {
  InitializeCriticalSection(&epoxy_lock);
  return TRUE;
}

static void epoxy_lock_acquire(void) {
  InitOnceExecuteOnce(&epoxy_init_once_flag, init_cs_cb, NULL, NULL);
  EnterCriticalSection(&epoxy_lock);
}

static void epoxy_lock_release(void) {
  LeaveCriticalSection(&epoxy_lock);
}

static void open_and_init(void) {
  if (epoxy_ready) return;

  epoxy_lock_acquire();
  if (epoxy_ready) { epoxy_lock_release(); return; }

  gl_module = LoadLibraryA(GL_LIB_PATH);
  if (!gl_module) {
    fprintf(stderr, "epoxy: could not open %s\n", GL_LIB_PATH);
    abort();
  }

  // Pre-resolve wglGetProcAddress for the extension-fallback path.
  wglGPA = (wglGetProcAddress_t)GetProcAddress(gl_module, "wglGetProcAddress");

  // Publish: all fields above are visible to any thread that sees this store.
  InterlockedExchange(&epoxy_ready, 1);

  epoxy_lock_release();
}

#else  // macOS + Linux

static void do_init(void) {
#if defined(__APPLE__)
  gl_handle = dlopen(GL_LIB_PATH, RTLD_LAZY | RTLD_GLOBAL);
  if (!gl_handle) {
    fprintf(stderr, "epoxy: could not open %s\n", GL_LIB_PATH);
    abort();
  }
#else
  // Linux: prefer glvnd libOpenGL, fall back to classic libGL.
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
#endif
}

static void open_and_init(void) {
  pthread_once(&epoxy_init_once, do_init);
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
    if (is_wgl_sentinel(result)) {
      result = NULL;
    }
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
