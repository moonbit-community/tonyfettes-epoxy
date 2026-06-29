name = "tonyfettes/epoxy-examples"

version = "0.1.0"

description = "Runnable examples for the epoxy GL dispatch library."

preferred_target = "native"

import {
  "tonyfettes/epoxy@0.1.0",
}

options(
  source: ".",
  "--moonbit-unstable-prebuild": "build.js",
)
