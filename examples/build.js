// Prebuild hook: emit the link flags the hello_gl demo needs to create a GL
// context. Making a current context is the window-system layer's job (CGL/EGL/
// GLX/WGL), which is the only reason this example links GL at all — epoxy
// itself only dlopens. Pick that library per platform: the OpenGL framework
// (CGL) on macOS, libGL (GLX) elsewhere. The epoxy library's own -ldl flag
// propagates in from its module's prebuild, so it is not repeated here.

const gl = process.platform === "darwin" ? "-framework OpenGL" : "-lGL";

console.log(
  JSON.stringify({
    link_configs: [
      { package: "feihaoxiang/epoxy-examples/hello_gl/main", link_flags: gl },
    ],
  }),
);
