name = "tonyfettes/epoxy"

version = "0.1.1"

description = "A MoonBit reimplementation of libepoxy: OpenGL function pointer dispatch."

license = "MIT"

repository = "https://github.com/moonbit-community/tonyfettes-epoxy"

readme = "README.md"

keywords = [ "opengl", "gl", "epoxy", "ffi", "bindings" ]

preferred_target = "native"

import {
  "tonyfettes/c@0.7.7",
}

options(
  source: ".",
  // Keep the published package to just the library: the generator and examples
  // are separate workspace modules (own moon.mod), and upstream is the vendored
  // reference C impl — none belong in a consumer's download.
  exclude: [ "upstream", "generator", "examples", "moon.work" ],
  "--moonbit-unstable-prebuild": "build.js",
)
