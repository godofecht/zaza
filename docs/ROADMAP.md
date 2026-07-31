# Zaza Roadmap

Short-term execution plan for making Zaza credible as a CMake replacement.

For the full parity matrix, priorities, and success criteria, see
[`docs/CMAKE_PARITY.md`](/Users/abhishekshivakumar/vex_zig/-Zaza/docs/CMAKE_PARITY.md).

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

Recently added:

- first-class test and benchmark API in `build_lib/test_suite.zig`
  (`addTest` / `addBench`), driving `examples/test_workflows` and
  `examples/bench_suite`

Still notably incomplete:

- stronger package discovery/import UX beyond the current producer/consumer proof
- broader cross-target/platform matrix in CI
- richer editor/IDE integration
- automatic toolchain strategy selection for things like C++20 modules

## 1) Core Build Graph
- split `CppExample` into real target primitives plus thin example wrappers
- add static/shared/interface/object library support
- add target-to-target dependency wiring with transitive usage requirements
- add graph tests covering include dirs, defines, link flags, and link order
- macOS universal (fat) binaries: build both arches and combine the slices with
  a toolchain-pure lipo-equivalent step ([#38](https://github.com/godofecht/zaza/issues/38))

## 2) Dependency and Package UX
- [done] lockfile with exact fetched hashes (`zaza.lock`, written by `fetch`)
- local dependency overrides for development
- package install/export layout that downstream projects can consume cleanly
- [done] `zaza deps` listing (source, lock state, on-disk presence)
- [done] `zaza clean-deps` to wipe `deps/` + `zig-out/deps`
- [done] cache info command (`zaza cache`, shows the Zig cache dirs + writability)

## 3) Project Workflows
- [done] first-class test target API (`test_suite.addTest`, labels/env/cwd/args)
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

- [done] first-class benchmark target API (`test_suite.addBench`,
  `examples/bench_suite`)
- [done] first-class test target model with labels/env/cwd/args encoded in the
  API (`test_suite.addTest`, `examples/test_workflows`)
- run the test and benchmark API end to end in CI (added to the macOS
  full-build job); running the whole `example-matrix` in CI still needs the
  `./zig` wrapper and the node/cmake/cross toolchain
- add toolchain-selection helpers for modules/sanitizers/LTO
- add a browser-oriented wasm example that goes beyond smoke testing into user-visible interaction patterns
