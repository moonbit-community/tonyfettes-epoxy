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
- **`main.mbt`** — everything GL: the GLSL 1.20 shader pair, client-side
  vertex arrays, and the per-frame rotate → clear → draw loop.

Notes on the GL choices:

- **GLSL 1.20 + client-side vertex arrays** because the demo context is the
  macOS legacy 2.1 compatibility profile.
- The per-frame animation demonstrates the `Bytes` lifetime rule: each frame's
  positions are packed into a fresh `Bytes`, handed to
  `gl_vertex_attrib_pointer` (which borrows and *stores* the pointer), and
  kept alive until `gl_draw_arrays` and the buffer swap have consumed them.
- `NSOpenGLView` is deprecated (Apple wants Metal) but remains the smallest
  zero-dependency way to put a legacy GL context on screen; a real app would
  use GLFW/SDL, and only the two `demo_window_*` functions would change.
