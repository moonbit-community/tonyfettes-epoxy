// Prebuild hook: emit the link flags the demos need to create a GL context.
// Making a current context is the window-system layer's job (CGL/EGL/GLX/WGL),
// which is the only reason these examples link GL at all — epoxy itself only
// dlopens. Pick that library per platform: the OpenGL framework (CGL) on
// macOS, libGL (GLX) elsewhere. The epoxy library's own -ldl flag propagates
// in from its module's prebuild, so it is not repeated here.

const gl = process.platform === "darwin" ? "-framework OpenGL" : "-lGL";
// The windowed demo additionally needs the toolkit that owns the window.
const windowed =
  process.platform === "darwin" ? `-framework Cocoa ${gl}` : gl;

console.log(
  JSON.stringify({
    link_configs: [
      { package: "tonyfettes/epoxy-examples/hello_gl/main", link_flags: gl },
      {
        package: "tonyfettes/epoxy-examples/triangle/main",
        link_flags: windowed,
      },
    ],
  }),
);
