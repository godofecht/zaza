# Vex

Vex is a Zig-driven build system for modern C, C++, Zig, CMake-interop, and WebAssembly workflows.

The project goal is straightforward: make new native projects feel simpler than CMake without giving up serious target graphs, package flows, generated code, cross-compilation, or browser-adjacent outputs.

## Why Vex

- Zig build graph as the control plane instead of a separate DSL
- First-class mixed-language workflows: C, C++, and Zig in one repo
- Real examples for generated sources, shared plugins, packaging, presets, CMake interop, and wasm
- One verified matrix command for the example surface

## Status

Vex is usable and heavily example-driven, but it is not pretending to have a final polished API yet.

Current reality:

- the verified example matrix is runnable with `zig build example-matrix`
- the repo includes package producer/consumer, mixed C/C++/Zig, wasm, browser demo, cross-compile, and CMake interop examples
- some flows remain environment-sensitive
  - `VEX_PRESET=asan` depends on sanitizer runtime availability
  - `VEX_PRESET=lto` depends on linker/toolchain configuration
  - the C++20 modules example uses LLVM Clang on this machine rather than `zig c++`

## Quick Start

Prerequisites:

- Zig 0.14.0 or newer
- Git for dependency fetch flows
- Python 3 for the local browser demo server/smoke path
- optional: `direnv` for repo-local cache setup

Clone and verify the repo:

```bash
git clone <repo-url>
cd <repo-dir>

# optional
direnv allow

zig build test
zig build example-matrix
```

Useful first commands:

```bash
zig build run-hello-vex
zig build package-consumer-run
zig build mixed-stack-run
zig build wasm-web-demo-smoke
zig build wasm-web-demo-serve
```

If a target needs external tools such as `git` or `cmake`, enable them explicitly:

```bash
VEX_SYSTEM_CMDS=1 zig build cmake-shim
```

## What It Covers

The current verified example surface includes:

- mixed Zig + C++ executables
- static, shared, object, and interface-style target graphs
- generated source and generated header workflows
- package install/export plus downstream consumption
- runtime assets under `zig-out/share/...`
- C ABI bindings between Zig and C++
- preset/profile-driven builds
- cross-compilation
- CMake-based dependency integration
- WebAssembly for WASI, host embedding, and browser delivery

Run the full matrix:

```bash
zig build example-matrix
```

## Example Highlights

These are the highest-signal example entry points:

| Workflow | Command |
| --- | --- |
| Mixed Zig + C++ | `zig build run-hello-vex` |
| Package producer / consumer | `zig build package-consumer-run` |
| Mixed C + C++ + Zig | `zig build mixed-stack-run` |
| Interface + object + static graph | `zig build interface-object-graph-run` |
| Shared plugin loading | `zig build shared-plugin-run` |
| Cross-compile artifact report | `zig build cross-compile-cli-report` |
| C++20 modules | `zig build cxx20-modules-run` |
| WASI artifact validation | `zig build wasm-wasi-report` |
| Host-loaded wasm exports | `zig build wasm-exports-run` |
| Browser wasm demo | `zig build wasm-web-demo-smoke` |

Full per-example explanations and diagrams live in [`docs/EXAMPLES.md`](docs/EXAMPLES.md).

## Build and Command Model

Current naming conventions:

- `<name>`: build or stage the artifact
- `<name>-run`: execute something real
- `<name>-report`: inspect or validate an artifact
- `<name>-serve`: start a local server

Examples:

```bash
zig build hello-vex
zig build run-hello-vex
zig build cross-compile-cli-report
zig build wasm-web-demo-serve
```

The practical syntax reference for the current repo surface lives in [`docs/SYNTAX_REFERENCE.md`](docs/SYNTAX_REFERENCE.md).

## Minimal Example

```zig
const std = @import("std");
const cpp = @import("build/cpp_example.zig");

pub fn build(b: *std.Build) !void {
    const exe = try cpp.CppExample{
        .name = "my_app",
        .kind = .executable,
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{"include"},
        .public_defines = &.{"MY_APP=1"},
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = .Zig,
        .main_build_system = .Zig,
        .cpp_std = "17",
    }.build(b);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run my_app");
    run_step.dependOn(&run_cmd.step);
}
```

For the broader syntax surface, use the reference docs instead of treating this README as API documentation.

## Replacing CMake

The intent is not to mimic CMake syntax one-for-one. The intent is to cover the workflows people actually need when starting new projects.

Rough mental mapping:

| CMake concept | Vex shape |
| --- | --- |
| `CMakeLists.txt` | `build.zig` |
| `add_executable()` | executable target / `CppExample{ .kind = .executable }` |
| `add_library(STATIC ...)` | `CppExample{ .kind = .static_library }` |
| `target_include_directories()` | include-dir fields on the target |
| `target_compile_definitions()` | `public_defines` / `private_defines` / config defines |
| `add_custom_command()` | `custom_commands` |
| `install()` / `export()` | install/export fields and Vex package metadata |
| `find_package()` consumer flow | package producer / consumer example |

See [`docs/CMAKE_PARITY.md`](docs/CMAKE_PARITY.md) and [`docs/ROADMAP.md`](docs/ROADMAP.md) for the parity framing.

## WebAssembly

Vex already has concrete wasm workflows:

```bash
zig build wasm-wasi-report
zig build wasm-exports-run
zig build wasm-web-demo
zig build wasm-web-demo-smoke
zig build wasm-web-demo-serve
```

`wasm-web-demo-serve` stages and serves a browser harness at `http://127.0.0.1:8000`.

## Documentation

- Examples guide: [`docs/EXAMPLES.md`](docs/EXAMPLES.md)
- Syntax reference: [`docs/SYNTAX_REFERENCE.md`](docs/SYNTAX_REFERENCE.md)
- Roadmap: [`docs/ROADMAP.md`](docs/ROADMAP.md)
- CMake parity framing: [`docs/CMAKE_PARITY.md`](docs/CMAKE_PARITY.md)
- JUCE on Windows notes: [`docs/JUCE_WINDOWS.md`](docs/JUCE_WINDOWS.md)
- Wiki site source: [`wiki`](wiki)
- Contribution guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Code of conduct: [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
- Security policy: [`SECURITY.md`](SECURITY.md)
- License: [`LICENSE`](LICENSE)

## Repository Layout

| Path | Purpose |
| --- | --- |
| [`build.zig`](build.zig) | root build graph |
| [`build_lib`](build_lib) | reusable build helpers |
| [`examples`](examples) | example projects and workflows |
| [`tests`](tests) | Zig-side test coverage |
| [`registry`](registry) | lightweight registry metadata |
| [`wiki`](wiki) | static docs site |

## Contributing

The current contribution bar is:

```bash
zig build test
zig build example-matrix
```

And keep changes scoped:

- do not mix generated junk into commits
- keep command names explicit and grep-friendly
- prefer verified example coverage over vague feature claims

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the repo workflow details.
