# epoxy (MoonBit)

A MoonBit reimplementation of [libepoxy](https://github.com/anholt/libepoxy):
OpenGL function-pointer dispatch that resolves entry points lazily via
`dlopen`/`dlsym` and caches them — so callers just use undecorated names like
`glGetString` without worrying about loaders, versions, or extensions.

The library package is the module root: import it as `tonyfettes/epoxy`. A
separate module — `tonyfettes/epoxy-generator` under `generator/` — parses the
Khronos registry (`registry/gl.xml`, 3299 commands) with the
[xml-mbt](https://github.com/moonbit-community/xml-mbt) pull-parser and emits
MoonBit dispatch wrappers + C call shims for the **3217** commands it can
express. The rest (callbacks, a few exotic pointer shapes, the platform-variant
`GLhandleARB`) are skipped, never miscompiled.

Keeping the generator in its own module means the library's dependency closure
stays minimal: consumers of `tonyfettes/epoxy` never inherit the build-time
toolchain (xml parser, async IO). The library depends only on
`moonbitlang/core`.

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

Three modules share one `moon.work` workspace: the library (root), the
generator, and the examples.

| Path | Role |
|------|------|
| `gl.mbt`, `resolver.mbt`, `version.mbt` | **The epoxy library** (module root, `tonyfettes/epoxy`): GL enum constants, the lazy `dlopen`/`dlsym` resolver + self-patching `Dispatch` slots, and the version/extension introspection API. |
| `epoxy.c` | Hand-written C: the `dlopen`/`dlsym` resolver. |
| `gl_generated.mbt` / `gl_generated.c` | **Generated** dispatch wrappers + per-signature C call shims (3197). |
| `internal/glinfo/` | Pure parsers for the `GL_VERSION`/`GL_EXTENSIONS` strings (the introspection logic, unit-tested in isolation). Module-internal — not part of the public API. |
| `generator/` | **The binding generator** — its own module, `tonyfettes/epoxy-generator`: `parse.mbt` (streaming registry parse), `emit.mbt` (classification + codegen), `main.mbt` (CLI driver), plus its private support packages `gen/` (the `GLxxx`→type table), `cdecl/` (C-declarator parser), `aliasgroup/` (union-find over `<alias>` edges). |
| `examples/` | A separate module (`tonyfettes/epoxy-examples`); see `hello_gl`. |
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

Like libepoxy, the generated wrappers have the **same signature as the GL
function** — no error channel. If an entry point can't be resolved (you called
something the current context doesn't provide) the dispatch `abort()`s with
`epoxy: glXxx() not found`, exactly as upstream does. That's a programming
error: gate version/extension-specific calls on `gl_version` / `has_gl_extension`
first, rather than wrapping every call. So a render loop reads as plain GL, with
no `raise`/`try` plumbing.

Context creation (CGL in the example) is deliberately *not* part of dispatch —
it stands in for the window-system layer (CGL/EGL/GLX/WGL) an app/toolkit
provides. epoxy itself only `dlopen`s.

## FFI marshalling categories

The ~40 `GLxxx` typedefs collapse onto a handful of representations, all decided
in `generator/gen/types.mbt`:

- **Scalar** (most params): `GLenum/GLuint`→`UInt`, `GLint/GLsizei`→`Int`,
  `GLfloat`→`Float`, `GLdouble`→`Double`, `GL(u)int64`→`(U)Int64`. Direct.
- **Pointer-width**: `GLintptr/GLsizeiptr`→`Int64`→C `intptr_t/ssize_t`.
- **Scalar arrays**: `const T*`/`T*` → `FixedArray[T]` (32/64-bit), `#borrow`'d.
- **Byte data / strings**: `void*`/`GLchar*`/byte buffers → `Bytes`; string
  returns decode to `String`.
- **String arrays**: `const GLchar *const *` → `FixedArray[Bytes]` (the layout
  already *is* the `char**` GL wants — `glShaderSource` &c.).
- **16-bit arrays**: `const GLshort*`/`GLhalf*` → `FixedArray[Int16]`/`[UInt16]`.
- **Opaque handles**: `GLsync`/`GLeglImageOES`/`GLeglClientBufferEXT`/
  `GLVULKANPROCNV` → distinct `#external` types (`pub type GLsync` &c.). All
  share the `void *` ABI, so the C cast needs no GL headers; the names keep the
  handles from being interchangeable.
- **Deferred**: callbacks (`GLDEBUGPROC`), `GLhandleARB` (a split ABI — `unsigned
  int` elsewhere, `void *` on Apple — we won't miscompile either), non-string
  pointer returns, `void**`/pointer-width arrays, OpenCL interop.

## Build & run

This is a multi-module workspace (`moon.work`). The module sets
`preferred_target = "native"`, so no `--target` flag is needed; link flags are
computed per-platform by a `build.js` prebuild script.

```sh
moon -C generator run .                     # regenerate bindings from gl.xml
moon test                                   # all unit tests
moon -C examples run hello_gl/main --release    # the demo (release: see examples/hello_gl)
```

The generator takes its paths on the command line (run `moon -C generator run .
-- --help` for the full list); the defaults point at the in-tree registry and
the library package, so the bare command above regenerates in place:

```sh
moon -C generator run . -- \
  --registry ../upstream/libepoxy/registry/gl.xml \
  --out-mbt  ../gl_generated.mbt \
  --out-c    ../gl_generated.c
```

## Generator coverage

| Category | Count | Status |
|----------|------:|--------|
| scalar / void / string + scalar/string/16-bit arrays + opaque handles | 3217 | ✅ generated |
| `void**` out-pointers (`glGetPointerv`, `glMultiDrawElements`, …) | 36 | deferred |
| `GLhandleARB` (platform-variant ABI; modern `GLuint` form is bound) | 23 | deferred |
| non-string pointer return (`void* glMapBuffer`) | 11 | deferred |
| pointer-width arrays (`GLintptr*` in `glBindBuffersRange`, …) | 5 | deferred |
| callback argument (`GLDEBUGPROC`) | 4 | deferred |
| non-char double-pointer arrays (`GLvdpauSurfaceNV*`) | 2 | deferred |
| OpenCL interop type (`glCreateSyncFromCLeventARB`) | 1 | deferred |

## Roadmap

1. ✅ Vertical slice: resolver + self-patching dispatch + scalar/pointer shims.
2. ✅ Generator: parse `registry/gl.xml`, emit bindings + C shims.
3. ✅ Pointer/array params — `Bytes`/`FixedArray` passthrough, `#borrow`'d.
4. ✅ Alias groups (`<alias>` fallback) + `epoxy_gl_version` / `is_desktop_gl` /
   `has_gl_extension`.
5. ✅ String arrays (`const GLchar *const *`) + 16-bit arrays.
6. ✅ Opaque object handles (`GLsync`, `GLeglImageOES`, `GLeglClientBufferEXT`,
   `GLVULKANPROCNV`) → distinct `#external` types.
7. Remaining shapes: non-string pointer returns (→ opaque `CPtr`), `void**`
   out-pointers, callbacks (`GLDEBUGPROC` trampoline). `GLhandleARB` needs a
   platform `#ifdef` typedef (split ABI) to bind without miscompiling.
8. GLES / EGL / GLX / WGL window-system layers; Linux + Windows loaders.
