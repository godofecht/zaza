# Vex Roadmap

Short-term, pragmatic steps to make Vex feel cohesive and useful as a CMake replacement.

## 1) UX polish
- `zig build run-cpp -- file.cpp` prints build args, output path, and runtime status
- Flag passthrough: `zig build run-cpp -- file.cpp -- -OReleaseFast -g`
- Parity: `zig build run-zig -- file.zig`

## 2) Dependency UX
- `vex deps` listing (source, build system, install prefix)
- `vex clean-deps` to wipe `deps/` + `zig-out/deps`
- Cache info command (shows `ZIG_*_CACHE_DIR` + writability)

## 3) CMake shim maturation
- Generate `compile_commands.json` for CMake deps
- Emit a manifest of include/lib paths for downstream tools
- Lockfile for fetched git SHAs

## 4) Examples
- C++20 modules example with 3+ CMake deps
- Mixed Zig + C + C++ example, end-to-end
