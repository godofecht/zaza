# Vex Roadmap

Short-term execution plan for making Vex credible as a CMake replacement.

For the full parity matrix, priorities, and success criteria, see
[`docs/CMAKE_PARITY.md`](/Users/abhishekshivakumar/vex_zig/-Vex/docs/CMAKE_PARITY.md).

## Current Status

Implemented and verified in the repo now:

- real example matrix via `zig build example-matrix`
- package producer/consumer flow
- mixed C + C++ + Zig example
- interface/object/static graph example
- workflow modes with args/env/cwd handling
- generated source and generated header examples
- shared plugin example
- resources/install layout example
- bindings example on the current build graph
- benchmark workflow example
- C++20 modules example via LLVM Clang
- WebAssembly examples:
  - WASI module validation
  - freestanding exported wasm module executed via Node
  - staged browser demo + local smoke test

Still notably incomplete:

- first-class benchmark/test API rather than example-only workflow coverage
- stronger package discovery/import UX beyond the current producer/consumer proof
- broader cross-target/platform matrix in CI
- richer editor/IDE integration
- automatic toolchain strategy selection for things like C++20 modules

## 1) Core Build Graph
- split `CppExample` into real target primitives plus thin example wrappers
- add static/shared/interface/object library support
- add target-to-target dependency wiring with transitive usage requirements
- add graph tests covering include dirs, defines, link flags, and link order

## 2) Dependency and Package UX
- lockfile with exact fetched revisions/hashes
- local dependency overrides for development
- package install/export layout that downstream projects can consume cleanly
- `vex deps` listing (source, build system, install prefix, lock state)
- `vex clean-deps` to wipe `deps/` + `zig-out/deps`
- cache info command (shows `ZIG_*_CACHE_DIR` + writability)

## 3) Project Workflows
- first-class test target API
- custom-command / generated-source support
- presets for `debug`, `release`, `asan`, and `lto`
- parity command for `zig build run-zig -- file.zig`
- `zig build run-cpp -- file.cpp -- <extra flags>` polish

## 4) CMake Interop
- generate `compile_commands.json` for CMake deps
- emit include/lib/define manifests for downstream tools
- improve CMake shim diagnostics and failure reporting
- import package metadata from installed CMake deps where feasible

## 5) Proof Projects
- C++ library + executable + tests + install/export example
- generated-code example
- mixed Zig + C + C++ example, end-to-end
- C++20 modules example with multiple third-party deps

## Next Best Work

- add a first-class benchmark target API rather than ad hoc benchmark examples
- add a first-class test target model with labels/env/cwd/args encoded in the API
- add CI jobs that run `zig build example-matrix`
- add toolchain-selection helpers for modules/sanitizers/LTO
- add a browser-oriented wasm example that goes beyond smoke testing into user-visible interaction patterns
