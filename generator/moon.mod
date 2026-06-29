name = "feihaoxiang/epoxy-generator"

version = "0.1.0"

description = "Binding generator for epoxy: parses the Khronos GL registry and emits MoonBit dispatch wrappers + C call shims."

preferred_target = "native"

import {
  "Milky2018/xml@0.2.0",
  "moonbitlang/async@0.19.4",
}

options(
  source: ".",
)
