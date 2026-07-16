// Prebuild hook: emit the epoxy library's platform-specific link flags.
//
// epoxy resolves GL entry points itself with dlopen/dlsym (Unix) /
// LoadLibrary (Windows), so the only system libraries it links are:
//   - Linux:   -ldl (dlopen) + -lpthread (mutex for one-time init)
//   - macOS:   nothing (dlopen + pthread are in libSystem)
//   - Windows: nothing (LoadLibrary is in kernel32, linked by default)
//
// These flags propagate into any executable that links epoxy (e.g. the
// examples module), so they live here rather than being hardcoded per package.

function link_flags() {
  switch (process.platform) {
    case "linux":
      return "-ldl -lpthread";
    default:
      return "";
  }
}

console.log(
  JSON.stringify({
    link_configs: [{ package: "tonyfettes/epoxy", link_flags: link_flags() }],
  }),
);
