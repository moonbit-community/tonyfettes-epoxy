# hello_gl

A single end-to-end smoke test of the `tonyfettes/epoxy` dispatch library: it
makes a current GL context, then drives a cross-section of generated bindings —
every FFI marshalling shape the generator can emit — against a live driver.

Run it from the repository root:

```sh
moon -C examples run hello_gl/main --release
```

`--release` is required on macOS: the debug build links with TCC, which does not
understand the `-framework OpenGL` flag the prebuild emits for the context
helper. The release build uses the system C compiler, which does.

Expected output on macOS (Apple OpenGL 2.1 / Metal):

```
GL_VERSION  = 2.1 Metal - 90.5
GL_VENDOR   = Apple
GL_RENDERER = Apple M3 Max
glGetError  = 0 (GL_NO_ERROR=0)
gl_version  = 21 (2.1)
is_desktop  = true
has GL_APPLE_vertex_array_object = true
GL_MAX_TEXTURE_SIZE = 16384
glGenBuffers -> [1, 2, 3]
glShaderSource+compile ok = true
glColor3sv round-trip = [1, 0, 0]
```

What each line proves:

| Call | Shape exercised |
|------|-----------------|
| `gl_get_string` | pointer return `const GLubyte*` → `String` |
| `gl_get_error` | pure scalar, no args |
| `gl_version` / `is_desktop_gl` / `has_gl_extension` | the introspection API (`@glinfo` parsers over live GL strings) |
| `gl_get_integerv` | scalar-array out-param → `FixedArray[Int]` |
| `gl_gen_buffers` | scalar-array out-param → `FixedArray[UInt]` |
| `gl_shader_source` | `const GLchar *const *` string array → `FixedArray[Bytes]` |
| `gl_color3sv` | 16-bit array → `FixedArray[Int16]` |

`demo_context.c` (CGL) stands in for the window-system layer an app/toolkit
provides — it is the only reason the example links the OpenGL framework. epoxy
itself only `dlopen`s. That code is the app's job, not the library's, so it
lives here in the example rather than in `tonyfettes/epoxy`.
