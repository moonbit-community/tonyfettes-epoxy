# epoxy (MoonBit)

A MoonBit reimplementation of [libepoxy](https://github.com/anholt/libepoxy):
OpenGL function-pointer dispatch that resolves entry points lazily via
`dlopen`/`dlsym` and caches them — so callers just use undecorated names like
`glGetString` without worrying about loaders, versions, or extensions.

**Milestone 1 — vertical slice:** an end-to-end proof that the dispatch
mechanism works on MoonBit's native (C) backend.

**Milestone 2 — binding generator:** `src/generator` parses the Khronos
registry (`registry/gl.xml`, 3299 commands) with the [xml-mbt](upstream/xml-mbt)
pull-parser and emits MoonBit dispatch wrappers + C call shims for the 1511
commands with scalar/void/string signatures. The demo now runs entirely on
generated bindings.

## Status

Proven working on macOS (arm64, Apple OpenGL 2.1 / Metal):

```
$ moon run src/main --target native
GL_VERSION  = 2.1 Metal - 90.5
GL_VENDOR   = Apple
GL_RENDERER = Apple M3 Max
glGetError  = 0 (GL_NO_ERROR=0)
```

`glGetString` exercises the pointer-return path (`const GLubyte*` → `String`);
`glGetError` exercises the pure-scalar path (`GLenum`, no args). Both are
resolved on first call via `dlopen`/`dlsym`, cached in a self-patching dispatch
slot, then invoked through a per-signature C shim.

## Layout

| Path | Role |
|------|------|
| `src/gen/types.mbt` | **The type-mapping table** — single source of truth mapping every `GLxxx` typedef in `registry/gl.xml` to its MoonBit type, C type, and FFI marshalling category. Drives the generator. |
| `src/gen/types_test.mbt` | Tests, incl. a coverage test asserting every `<ptype>` used in gl.xml command signatures is mapped. |
| `src/generator/` | **The binding generator**: `parse.mbt` (streaming registry parse), `emit.mbt` (classification + codegen), `main.mbt` (driver). |
| `src/epoxy/epoxy_stub.c` | Hand-written C: the `dlopen`/`dlsym` resolver + demo offscreen-context helper. |
| `src/epoxy/gl_generated_stub.c` | **Generated** per-signature C call shims (1511). |
| `src/epoxy/resolver.mbt` | FFI declarations + the lazy GL-lib handle and self-patching `Dispatch` slots. |
| `src/epoxy/gl_generated.mbt` | **Generated** MoonBit dispatch wrappers (1511). |
| `src/epoxy/gl.mbt` | Hand-written support: GL enum constants, the UTF-8 decoder, demo context helper. |
| `src/main/main.mbt` | Demo. |
| `upstream/libepoxy` | The reference C implementation (submodule), incl. `registry/*.xml`. |

## How dispatch works

1. `Dispatch::new("glGetString")` creates a slot with an empty cached pointer.
2. First call to `gl_get_string` → `Dispatch::get` → `resolve("glGetString")`:
   `dlopen` the GL library once (cached), then `dlsym` the entry point.
3. The resolved `void*` is cached in the slot and passed to the C shim
   `epoxy_call_GetString`, which casts it to the right function-pointer type,
   calls it, and marshals the result back across the FFI boundary.
4. Subsequent calls skip resolution — just cache read + shim call.

Context creation (CGL here) is deliberately *not* part of dispatch — it stands
in for the window-system layer (CGL/EGL/GLX/WGL) an app/toolkit provides.

## Type categories (FFI marshalling)

The ~40 `GLxxx` typedefs collapse onto a handful of representations:

- **Scalar** (~95% of params): `GLenum/GLuint/GLbitfield`→`UInt`, `GLint/GLsizei`→`Int`, `GLfloat`→`Float`, `GLdouble`→`Double`, `GL(u)int64`→`(U)Int64`, etc. Direct, no marshalling.
- **PtrSized**: `GLintptr/GLsizeiptr`→`Int64`→C `intptr_t/ssize_t`. Must not be narrowed.
- **Pointer**: arrays/buffers/strings/in-out params → `Bytes`/`FixedArray` (via `#borrow`).
- **Opaque**: `GLsync`, `GLhandleARB`, egl image/buffer → `#external type`.
- **Callback** (deferred): `GLDEBUGPROC` family — needs a MoonBit→C trampoline.

## Build & run

```sh
moon run src/generator --target native   # regenerate bindings from gl.xml
moon run src/main --target native         # demo (runs on generated bindings)
moon test src/gen                         # type-table tests
```

Note: `moon build` (whole project) tries to link the `epoxy` *library* package
as an executable and fails with an `_main` undefined error — a native-backend
quirk. Build/run a specific package (`moon build src/main --target native`).

## Roadmap

1. ✅ Vertical slice: resolver + self-patching dispatch + scalar/pointer shims.
2. ✅ Generator: parse `registry/gl.xml`, emit bindings + C shims for the 1511
   scalar/void/string commands.
3. ✅ Pointer/array params — faithful `Bytes`/`FixedArray` passthrough
   (`#borrow`'d). 3084 commands now generated.
4. Remaining shapes: `const GLchar* const*` string arrays, 16-bit arrays,
   non-string pointer returns, callbacks (`GLDEBUGPROC`).
5. Alias groups + provider priority + `epoxy_gl_version` / `has_extension`.
6. GLES / EGL / GLX / WGL window-system layers.
7. Linux (`libGL.so.1` path is already wired) + Windows (`wglGetProcAddress`).

### Generator coverage (current)

| Category | Count | Status |
|----------|------:|--------|
| scalar / void / string + pointer-array | 3084 | ✅ generated |
| deferred pointer shape (`**`, 16-bit, opaque) | 156 | deferred |
| unknown / opaque scalar type | 44 | deferred |
| non-string pointer return | 11 | deferred |
| callback argument | 4 | deferred |

Pointer params pass through faithfully: `const T*`/`T*` → `FixedArray[T]`
(float/double/int32/uint32/int64/uint64), `void*`/`GLchar*`/byte data → `Bytes`,
all `#borrow`'d. The demo exercises this end-to-end — `glGetIntegerv` reads
`GL_MAX_TEXTURE_SIZE` into a `FixedArray[Int]`, `glGenBuffers` fills a
`FixedArray[UInt]`. 16-bit arrays (no native fixed-width array), `**`, and
opaque-pointer params remain deferred.
```
