name = "feihaoxiang/epoxy"

version = "0.1.0"

description = "A MoonBit reimplementation of libepoxy: OpenGL function pointer dispatch."

preferred_target = "native"

options(
  source: ".",
  exclude: [ "upstream" ],
  "--moonbit-unstable-prebuild": "build.js",
)
