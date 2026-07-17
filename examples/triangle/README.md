# triangle

The classic first render, in a real window: an RGB gradient triangle spinning
at ~60 fps until you close it. MoonBit drives every GL call through
`tonyfettes/epoxy`; a small Objective-C stub (`demo_window.m`) owns the window
and the event loop, the way a toolkit would.

Run it from the repository root (macOS only):

```sh
moon run ./examples/triangle/main --release
```

`--release` is required on macOS: the debug build links with TCC, which
understands neither Objective-C nor the `-framework` flags the prebuild emits.
The release build uses the system clang, which does.

Division of labor, mirroring how epoxy is meant to be used:

- **`demo_window.m`** — the window-system layer: `NSWindow` + `NSOpenGLView`
  (legacy 2.1 context), `demo_window_open()` to create it and
  `demo_window_frame()` to swap buffers and pump events. This is the only
  reason the demo links Cocoa/OpenGL; epoxy itself only `dlopen`s.
- **`main.mbt`** — everything GL: the GLSL 1.20 shader pair, vertex buffer
  objects, and the per-frame update → rotate → clear → draw loop.

Notes on the GL choices:

- **GLSL 1.20 + VBOs** work on the macOS OpenGL 2.1 compatibility context while
  keeping MoonBit-managed arrays out of retained OpenGL state.
- Colors are uploaded once with `gl_buffer_data`. Position storage is reserved
  with `gl_buffer_allocate` and refreshed each frame with
  `gl_buffer_sub_data`; each CPU array may be released immediately after its
  upload returns. `gl_vertex_attrib_pointer` records a VBO byte offset.
- `NSOpenGLView` is deprecated (Apple wants Metal) but remains the smallest
  zero-dependency way to put a legacy GL context on screen; a real app would
  use GLFW/SDL, and only the two `demo_window_*` functions would change.
