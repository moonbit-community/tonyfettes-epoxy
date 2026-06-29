// Prebuild hook: emit the epoxy library's platform-specific link flags.
//
// epoxy resolves GL entry points itself with dlopen/dlsym, so the only system
// library it links is the dynamic loader — and only on platforms that split it
// out of libc. macOS folds dlopen into libSystem, so nothing is needed there.
// These flags propagate into any executable that links epoxy (e.g. the
// examples module), so they live here rather than being hardcoded per package.

const dl = process.platform === "linux" ? "-ldl" : "";

console.log(
  JSON.stringify({
    link_configs: [{ package: "tonyfettes/epoxy", link_flags: dl }],
  }),
);
