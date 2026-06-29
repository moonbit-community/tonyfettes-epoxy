name = "feihaoxiang/epoxy"

version = "0.1.0"

description = "A MoonBit reimplementation of libepoxy: OpenGL function pointer dispatch."

preferred_target = "native"

import {
  "Milky2018/xml@0.2.0",
  "moonbitlang/async@0.19.4",
}

options(
  source: ".",
  exclude: [ "upstream" ],
  "--moonbit-unstable-prebuild": "build.js",
)
