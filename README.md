# epoxy (MoonBit)

A MoonBit reimplementation of [libepoxy](https://github.com/anholt/libepoxy):
OpenGL function-pointer dispatch that resolves entry points lazily via
`dlopen`/`dlsym` and caches them — so callers just use undecorated names like
`glGetString` without worrying about loaders, versions, or extensions.

The library package is the module root: import it as `tonyfettes/epoxy`. A
separate module — `tonyfettes/epoxy-generator` under `generator/` — parses the
Khronos registry (`registry/gl.xml`, 3299 commands) with the
[xml-mbt](https://github.com/moonbit-community/xml-mbt) pull-parser and emits
MoonBit dispatch wrappers for **3211** commands, plus all
**6061** GL enum constants. The rest (callbacks, a few exotic pointer shapes,
the platform-variant `GLhandleARB`) are skipped, never miscompiled; six commands
with safer public shapes are implemented entirely by hand.

Each wrapper calls its resolved entry point **directly through a `FuncRef`**
typed to the GL function's exact ABI — there is no per-command C shim. The
hand-written C file (`epoxy.c`) provides the `dlopen`/`dlsym` resolver and a few
private pointer ABI helpers; C-string results are copied into MoonBit-owned
bytes by the same small FFI layer.

Keeping the generator in its own module means the library's dependency closure
stays minimal: consumers of `tonyfettes/epoxy` never inherit the build-time
toolchain (xml parser, async IO). The library depends only on
`moonbitlang/core`; its small native-pointer representation and borrow helpers
are package-private.

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

See [`examples/hello_gl`](examples/hello_gl/) for what each line proves. For an
actual render, [`examples/triangle`](examples/triangle/) draws the classic RGB
gradient triangle in a window (Cocoa, macOS only), spinning until you close it:

```
$ moon run ./examples/triangle/main --release
```

## Layout

Three modules share one `moon.work` workspace: the library (root), the
generator, and the examples.

| Path | Role |
|------|------|
| `resolver.mbt`, `version.mbt`, `handles.mbt` | **The epoxy library** (module root, `tonyfettes/epoxy`): the lazy `dlopen`/`dlsym` resolver + self-patching `Dispatch` slots, the version/extension introspection API, and the opaque-handle types. |
| `epoxy.c` | Hand-written C: the `dlopen`/`dlsym` resolver and private pointer ABI helpers. |
| `gl.mbt` | Hand-written safe GL wrappers for packed buffer uploads and buffer-backed vertex attributes. |
| `gl_generated.mbt` | **Generated** MoonBit `FuncRef` dispatch wrappers (3211) — no C shim. |
| `gl_generated_enums.mbt` | **Generated** GL enum constants (`pub const GL_* : UInt/UInt64/Int`, 6061). |
| `internal/glinfo/` | Pure parsers for the `GL_VERSION`/`GL_EXTENSIONS` strings (the introspection logic, unit-tested in isolation). Module-internal — not part of the public API. |
| `generator/` | **The binding generator** — its own module, `tonyfettes/epoxy-generator`: `parse.mbt` (streaming registry parse), `emit.mbt` (classification + codegen), `main.mbt` (CLI driver), plus its private support packages `gen/` (the `GLxxx`→type table), `cdecl/` (C-declarator parser), `aliasgroup/` (union-find over `<alias>` edges). |
| `examples/` | A separate module (`tonyfettes/epoxy-examples`); see `hello_gl` and `triangle`. |
| `upstream/libepoxy` | The reference C implementation (submodule), incl. `registry/*.xml`. |

## How dispatch works

1. `Dispatch::with_aliases("glGenVertexArrays", [...])` creates a slot with an
   empty cached pointer and its alias group's fallback names.
2. First call → `Dispatch::get` → `dlopen` the GL library once (cached), then
   `dlsym` the primary name, falling back through the alias names.
3. The resolved package-private `Pointer[Unit]` is cached in the slot and
   reinterpreted into a `FuncRef` whose type lowers to the GL function's exact
   ABI. The wrapper borrows any call-scoped `FixedArray`/`Bytes` param into a raw
   pointer, calls the `FuncRef` directly, and
   narrows any sub-word return (e.g. `GLboolean`'s `unsigned char`) back to its
   width.
4. Subsequent calls skip resolution — just cache read + direct `FuncRef` call.

> **Why the sub-word narrow?** MoonBit lowers every `FuncRef` return (`Bool`,
> `Byte`, …) to `int32_t` and reads the whole return register, so a GL function
> that returns `unsigned char`/`short` would leave the high bits unspecified per
> the psABI. The generated wrapper always masks/sign-extends the low byte/halfword
> — the same fixup the old C shim's `(T)` cast did, now done MoonBit-side.

Like libepoxy, generated public wrappers preserve the GL function's argument
shape and have no error channel. A small hand-written layer exposes safer
shapes for commands where raw `void*` is ambiguous. `gl_buffer_data` and
`gl_buffer_sub_data` accept packed numeric `FixedArray[T]` values and derive the
byte count, while `gl_buffer_allocate` represents the `NULL` allocation form.
`gl_vertex_attrib_pointer` accepts only a byte offset into the currently bound
`GL_ARRAY_BUFFER`, so OpenGL never retains a pointer into MoonBit-managed
memory. These six GL commands are omitted from generated output and implemented
entirely in `gl.mbt`. If an entry point can't be resolved (you called something
the current context doesn't provide) the dispatch `abort()`s with `epoxy:
glXxx() not found`, exactly as upstream does. That's a programming error: gate
version/extension-specific calls on `gl_version` / `has_gl_extension` first,
rather than wrapping every call. So a render loop reads as plain GL, with no
`raise`/`try` plumbing.

Context creation (CGL in the example) is deliberately *not* part of dispatch —
it stands in for the window-system layer (CGL/EGL/GLX/WGL) an app/toolkit
provides. epoxy itself only `dlopen`s.

## FFI marshalling categories

The ~40 `GLxxx` typedefs collapse onto a handful of representations, all decided
in `generator/gen/types.mbt`:

- **Scalar** (most params): `GLenum/GLuint`→`UInt`, `GLint/GLsizei`→`Int`,
  `GLfloat`→`Float`, `GLdouble`→`Double`, `GL(u)int64`→`(U)Int64`. Direct.
- **Pointer-width**: `GLintptr/GLsizeiptr`→`Int64` (== `intptr_t/ssize_t` on the
  64-bit native targets).
- **Scalar arrays**: `const T*`/`T*` → `FixedArray[T]`, borrowed to a
  package-private `Pointer[T]` for the call.
- **Byte data / strings**: `void*`/`GLchar*`/byte buffers → `Bytes` (borrowed to
  a package-private `Pointer[Byte]`); string returns decode to `String` via
  `epoxy_cstr`.
- **String arrays**: `const GLchar *const *` → `FixedArray[Bytes]` (the layout
  already *is* the `char**` GL wants — `glShaderSource` &c.).
- **16-bit arrays**: `const GLshort*`/`GLhalf*` → `FixedArray[Int16]`/`[UInt16]`.
- **Buffer uploads**: `gl_buffer_data`/`gl_buffer_sub_data` accept
  `FixedArray[T]` where `T` is one of the sealed packed scalar `GlData` types;
  the wrappers derive the exact byte count and borrow the array only for the
  copying call. `gl_buffer_allocate` allocates uninitialized storage without a
  host array.
- **Buffer-backed vertex attributes**: `gl_vertex_attrib_pointer` accepts the
  GL element type plus an `Int64` byte offset into the bound
  `GL_ARRAY_BUFFER`. Client-side arrays and public pointers are deliberately not
  part of this API.
- **Opaque handles**: `GLsync`/`GLeglImageOES`/`GLeglClientBufferEXT`/
  `GLVULKANPROCNV` → distinct `#external` types (`pub type GLsync` &c.). All
  share the `void *` ABI, so they cross a `FuncRef` as-is; the names keep the
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
  --registry  ../upstream/libepoxy/registry/gl.xml \
  --out-mbt   ../gl_generated.mbt \
  --out-enums ../gl_generated_enums.mbt
```

## Generator coverage

| Category | Count | Status |
|----------|------:|--------|
| scalar / void / string + scalar/string/16-bit arrays + opaque handles | 3211 | ✅ generated |
| safe buffer upload/subdata + buffer-backed vertex attributes | 6 | ✅ hand-written |
| `void**` out-pointers (`glGetPointerv`, `glMultiDrawElements`, …) | 36 | deferred |
| `GLhandleARB` (platform-variant ABI; modern `GLuint` form is bound) | 23 | deferred |
| non-string pointer return (`void* glMapBuffer`) | 11 | deferred |
| pointer-width arrays (`GLintptr*` in `glBindBuffersRange`, …) | 5 | deferred |
| callback argument (`GLDEBUGPROC`) | 4 | deferred |
| non-char double-pointer arrays (`GLvdpauSurfaceNV*`) | 2 | deferred |
| OpenCL interop type (`glCreateSyncFromCLeventARB`) | 1 | deferred |

## Roadmap

1. ✅ Vertical slice: resolver + self-patching dispatch + scalar/pointer calls.
2. ✅ Generator: parse `registry/gl.xml`, emit `FuncRef` bindings (no C shims).
3. ✅ Pointer/array params — generated call-scoped `Bytes`/`FixedArray`
   bindings, packed generic buffer uploads, and VBO-only vertex attributes.
4. ✅ Alias groups (`<alias>` fallback) + `epoxy_gl_version` / `is_desktop_gl` /
   `has_gl_extension`.
5. ✅ String arrays (`const GLchar *const *`) + 16-bit arrays.
6. ✅ Opaque object handles (`GLsync`, `GLeglImageOES`, `GLeglClientBufferEXT`,
   `GLVULKANPROCNV`) → distinct `#external` types.
7. ✅ GL enum constants — all 6061 `<enum>`s → `pub const` (`UInt`/`UInt64`/`Int`).
8. Remaining shapes: non-string pointer returns (→ private opaque pointer), `void**`
   out-pointers, callbacks (`GLDEBUGPROC` trampoline). `GLhandleARB` needs a
   platform `#ifdef` typedef (split ABI) to bind without miscompiling.
9. GLES / EGL / GLX / WGL window-system layers; Linux + Windows loaders.
