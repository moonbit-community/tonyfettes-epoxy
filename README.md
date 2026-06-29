# epoxy (MoonBit)

A MoonBit reimplementation of [libepoxy](https://github.com/anholt/libepoxy):
OpenGL function-pointer dispatch that resolves entry points lazily via
`dlopen`/`dlsym` and caches them — so callers just use undecorated names like
`glGetString` without worrying about loaders, versions, or extensions.

The library package is the module root: import it as `feihaoxiang/epoxy`. A
binding generator parses the Khronos registry (`registry/gl.xml`, 3299 commands)
with the [xml-mbt](https://github.com/moonbit-community/xml-mbt) pull-parser and
emits MoonBit dispatch wrappers + C call shims for the **3197** commands it can
express. The rest (callbacks, opaque handles, a few exotic pointer shapes) are
skipped, never miscompiled.

## Status

Proven working on macOS (arm64, Apple OpenGL 2.1 / Metal). The `hello_gl`
example drives a cross-section of generated bindings against a live driver:

```
$ moon -C examples run hello_gl/main --release
GL_VERSION  = 2.1 Metal - 90.5
gl_version  = 21 (2.1)
is_desktop  = true
has GL_APPLE_vertex_array_object = true
GL_MAX_TEXTURE_SIZE = 16384
glGenBuffers -> [1, 2, 3]
glShaderSource+compile ok = true
glColor3sv round-trip = [1, 0, 0]
```

See [`examples/hello_gl`](examples/hello_gl/) for what each line proves.

## Layout

The module is a root package plus a handful of internal support packages. The
generator runs as a normal `moon run`, writing its output into the root package.

| Path | Role |
|------|------|
| `gl.mbt`, `resolver.mbt`, `version.mbt` | **The epoxy library** (module root, `feihaoxiang/epoxy`): GL enum constants, the lazy `dlopen`/`dlsym` resolver + self-patching `Dispatch` slots, and the version/extension introspection API. |
| `epoxy_stub.c` | Hand-written C: the `dlopen`/`dlsym` resolver. |
| `gl_generated.mbt` / `gl_generated_stub.c` | **Generated** dispatch wrappers + per-signature C call shims (3197). |
| `gen/` | **The type-mapping table** — single source of truth mapping every `GLxxx` typedef to its MoonBit type, C type, and FFI marshalling category. Drives the generator. |
| `cdecl/` | C-declarator parser for the registry's `<param>`/`<proto>` fragments. |
| `aliasgroup/` | Union-find over `<alias>` edges, so a binding can fall back to its equivalent entry-point names. |
| `glinfo/` | Pure parsers for the `GL_VERSION`/`GL_EXTENSIONS` strings (the introspection logic, unit-tested in isolation). |
| `generator/` | **The binding generator**: `parse.mbt` (streaming registry parse), `emit.mbt` (classification + codegen), `main.mbt` (driver). |
| `examples/` | A separate module (`feihaoxiang/epoxy-examples`); see `hello_gl`. |
| `upstream/libepoxy` | The reference C implementation (submodule), incl. `registry/*.xml`. |

## How dispatch works

1. `Dispatch::with_aliases("glGenVertexArrays", [...])` creates a slot with an
   empty cached pointer and its alias group's fallback names.
2. First call → `Dispatch::get` → `dlopen` the GL library once (cached), then
   `dlsym` the primary name, falling back through the alias names.
3. The resolved `void*` is cached in the slot and passed to the generated C
   shim, which casts it to the right function-pointer type, calls it, and
   marshals the result back across the FFI boundary.
4. Subsequent calls skip resolution — just cache read + shim call.

Context creation (CGL in the example) is deliberately *not* part of dispatch —
it stands in for the window-system layer (CGL/EGL/GLX/WGL) an app/toolkit
provides. epoxy itself only `dlopen`s.

## FFI marshalling categories

The ~40 `GLxxx` typedefs collapse onto a handful of representations, all decided
in `gen/types.mbt`:

- **Scalar** (most params): `GLenum/GLuint`→`UInt`, `GLint/GLsizei`→`Int`,
  `GLfloat`→`Float`, `GLdouble`→`Double`, `GL(u)int64`→`(U)Int64`. Direct.
- **Pointer-width**: `GLintptr/GLsizeiptr`→`Int64`→C `intptr_t/ssize_t`.
- **Scalar arrays**: `const T*`/`T*` → `FixedArray[T]` (32/64-bit), `#borrow`'d.
- **Byte data / strings**: `void*`/`GLchar*`/byte buffers → `Bytes`; string
  returns decode to `String`.
- **String arrays**: `const GLchar *const *` → `FixedArray[Bytes]` (the layout
  already *is* the `char**` GL wants — `glShaderSource` &c.).
- **16-bit arrays**: `const GLshort*`/`GLhalf*` → `FixedArray[Int16]`/`[UInt16]`.
- **Deferred**: callbacks (`GLDEBUGPROC`), opaque handles (`GLsync`), non-string
  pointer returns, `void**`/non-char double pointers.

## Build & run

This is a multi-module workspace (`moon.work`). The module sets
`preferred_target = "native"`, so no `--target` flag is needed; link flags are
computed per-platform by a `build.js` prebuild script.

```sh
moon run generator                         # regenerate bindings from gl.xml
moon test                                  # all unit tests
moon -C examples run hello_gl/main --release   # the demo (release: see examples/hello_gl)
```

## Generator coverage

| Category | Count | Status |
|----------|------:|--------|
| scalar / void / string + scalar-array + string-array + 16-bit-array | 3197 | ✅ generated |
| remaining pointer shape (`void**`, pointer-width, non-char `**`) | 43 | deferred |
| unknown / opaque scalar type (`GLsync`, `GLhandleARB`, …) | 44 | deferred |
| non-string pointer return (`void* glMapBuffer`) | 11 | deferred |
| callback argument (`GLDEBUGPROC`) | 4 | deferred |

## Roadmap

1. ✅ Vertical slice: resolver + self-patching dispatch + scalar/pointer shims.
2. ✅ Generator: parse `registry/gl.xml`, emit bindings + C shims.
3. ✅ Pointer/array params — `Bytes`/`FixedArray` passthrough, `#borrow`'d.
4. ✅ Alias groups (`<alias>` fallback) + `epoxy_gl_version` / `is_desktop_gl` /
   `has_gl_extension`.
5. ✅ String arrays (`const GLchar *const *`) + 16-bit arrays.
6. Remaining shapes: non-string pointer returns (→ opaque `CPtr`), `void**`
   out-pointers, callbacks (`GLDEBUGPROC` trampoline).
7. GLES / EGL / GLX / WGL window-system layers; Linux + Windows loaders.
