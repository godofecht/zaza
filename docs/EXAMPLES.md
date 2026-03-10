# Vex Examples Guide

This document explains what each verified example is doing, why it exists, and
which target to run.

The fastest way to exercise the whole verified surface is:

```bash
zig build example-matrix
```

## Naming Conventions

- `foo`: build or stage the example artifacts
- `foo-run`: execute the example
- `foo-report`: inspect or validate an artifact when execution is not the point
- `foo-serve`: start a local server for a staged web artifact

## Syntax Legend

Each example also names the syntax it is demonstrating.

- `CppExample.kind`: target shape such as executable, static library, or shared library
- `custom_commands`: pre-build commands that generate sources or headers
- `generated_source_files`: generated `.c` / `.cpp` inputs that still need compilation
- `public_include_dirs` / `public_defines` / `public_link_libs`: usage that should propagate to downstream targets
- `BuildConfig`: per-configuration flags, defines, link settings, and mode selection
- nested build: a root target that intentionally shells out into another `build.zig`
- wasm target: an example whose important output is a `.wasm` artifact rather than a native executable

## 1. Hello Vex

Targets:

```bash
zig build hello-vex
zig build run-hello-vex
```

What it proves:
- mixed Zig and C++ artifacts can live in one build graph
- Vex can build both and run both from one top-level step

Syntax focus:
- root target naming with `hello-vex` and `run-hello-vex`
- mixed-language orchestration with a Zig executable and a C++ executable in one graph

Diagram:

```text
main.zig  ---> hello_vex_zig
main.cpp  ---> hello_vex_cpp
                   |
                   +--> run-hello-vex
```

## 2. Package Producer / Consumer

Targets:

```bash
zig build package-producer-run
zig build package-consumer-run
```

What it proves:
- a library can be installed with headers, libs, and Vex package metadata
- a downstream project can consume the installed package from a separate build

Syntax focus:
- install/export fields such as `install_headers`, `install_libs`, and `export_cmake`
- nested build flow for a true downstream consumer
- package metadata resolved from `zig-out/share/vex/<name>.json`

Diagram:

```text
package_producer
  -> zig-out/include/package_math/...
  -> zig-out/lib/libpackage_math_*.a
  -> zig-out/share/vex/package_math.json

package_consumer
  -> reads package_math.json
  -> adds include/lib paths
  -> links and runs
```

## 3. Proof Library

Targets:

```bash
zig build proof-library
zig build proof-library-run
```

What it proves:
- basic static library + executable flow
- install/export metadata on a normal C++ library

Syntax focus:
- `CppExample.kind = .static_library`
- normal executable-to-library linking without extra generation steps

Diagram:

```text
proof_math.cpp ---> libproof_math
main.cpp -------> proof_library_app ---> run
```

## 4. Generated Source

Targets:

```bash
zig build generated-code
zig build generated-code-run
```

What it proves:
- a custom command can generate a `.cpp` file before compilation
- generated sources can flow through a normal target

Syntax focus:
- `custom_commands`
- `generated_source_files`

Diagram:

```text
generate_message.sh -> generated_message.cpp
generated_message.cpp + main.cpp -> generated_code_demo
```

## 5. Generated Header

Targets:

```bash
zig build generated-headers
zig build generated-headers-run
```

What it proves:
- a custom command can generate a header
- a library can include that generated header and an executable can then consume the library

Syntax focus:
- `custom_commands` for generated headers
- include-path wiring for generated outputs
- downstream propagation from library to executable

Diagram:

```text
generate_header.sh -> generated_message.hpp
generated_greeter.cpp -> generated_headers_lib
main.cpp + generated_headers_lib -> generated_headers_demo
```

## 6. Mixed C + C++ + Zig

Targets:

```bash
zig build mixed-stack
zig build mixed-stack-run
```

What it proves:
- a C static library can feed a C++ bridge library
- a Zig executable can link both and call through the stack

Syntax focus:
- mixed `C` + `C++` + `Zig` source sets
- multi-library composition across language boundaries

Diagram:

```text
mixed_core.c ----> libmixed_core
mixed_bridge.cpp -> libmixed_bridge -> links libmixed_core
main.zig --------> mixed_stack_demo -> links both libs
```

## 7. Interface / Object / Static Graph

Targets:

```bash
zig build interface-object-graph
zig build interface-object-graph-run
```

What it proves:
- object-library style composition
- interface usage propagation modeled in tests and reflected in a real build

Syntax focus:
- `CppExample.kind = .object_library`
- `CppExample.kind = .interface_library`
- `public_include_dirs` and `public_defines` propagation

Diagram:

```text
interface usage (include + define)
          |
          v
object_part.cpp -> graph_objects (.o)
core.cpp -------> graph_core (.a) + graph_objects
main.cpp -------> interface_object_graph_demo
```

## 8. Workflow Modes

Targets:

```bash
zig build test-workflows-run
zig build test-workflows-unit
zig build test-workflows-integration
```

What it proves:
- different run modes can use different args
- env vars can be injected per run
- cwd-sensitive fixtures can be read reliably

Syntax focus:
- multiple `*-run`-style workflow targets
- argument, env, and working-directory control

Diagram:

```text
test_workflows_demo
  + arg "unit"        + WORKFLOW_MODE=unit        + cwd=examples/test_workflows
  + arg "integration" + WORKFLOW_MODE=integration + cwd=examples/test_workflows
  + arg "smoke"       + WORKFLOW_MODE=smoke       + cwd=examples/test_workflows
```

## 9. Shared Plugin

Targets:

```bash
zig build shared-plugin
zig build shared-plugin-run
```

What it proves:
- shared library build support
- runtime dynamic loading with an executable host

Syntax focus:
- `CppExample.kind = .shared_library`
- runtime loading rather than normal static link-time consumption

Diagram:

```text
plugin.cpp -> shared_plugin.(dylib|so|dll)
host.cpp   -> shared_plugin_host
shared_plugin_host --dlopen--> shared_plugin
```

## 10. Preset Profiles

Targets:

```bash
zig build preset-profiles-run
VEX_PRESET=asan zig build preset-profiles-run
VEX_PRESET=lto zig build preset-profiles-run
```

What it proves:
- `VEX_PRESET` changes the selected build configuration set
- examples can make the active preset visible in output

Syntax focus:
- `VEX_PRESET`
- `BuildConfig`
- profile-driven configuration selection

Notes:
- on this machine, `asan` is blocked by missing sanitizer runtime support
- on this machine, `lto` is blocked unless the toolchain is using LLD

Diagram:

```text
VEX_PRESET -> presetConfigs(...) -> BuildConfig list -> example compile flags/defines
```

## 11. Cross-Compile CLI

Targets:

```bash
zig build cross-compile-cli
zig build cross-compile-cli-report
```

What it proves:
- a nested build can target a non-host triple
- the resulting artifact can be inspected even if it is not runnable on the host

Syntax focus:
- nested build invocation
- explicit target selection for non-host output
- `*-report` for artifact inspection

Diagram:

```text
main.zig --target x86_64-linux-musl--> cross_compile_cli
cross_compile_cli-report -------------> file(...) inspection
```

## 12. Resources Bundle

Targets:

```bash
zig build resources-bundle
zig build resources-bundle-run
```

What it proves:
- runtime assets can be staged into a stable layout under `zig-out/share`
- the executable can consume the staged resource by explicit path

Syntax focus:
- staged runtime assets
- install-style output layout under `zig-out/share/...`

Diagram:

```text
message.txt -> zig-out/share/resources_bundle/message.txt
main.cpp    -> resources_bundle_demo -> reads staged asset
```

## 13. Bindings

Targets:

```bash
zig build bindings
zig build bindings-run
```

What it proves:
- a Zig executable can call into a C++ library through a C ABI wrapper
- Zig module imports can stay small and explicit

Syntax focus:
- Zig FFI boundary design
- C ABI wrapper as the stable bridge to C++

Diagram:

```text
calculator.cpp + calculator_wrapper.cpp -> libcalculator_bindings
calculator.zig ------------------------> Zig FFI surface
main.zig ------------------------------> bindings_demo
```

## 14. Benchmark Workflow

Targets:

```bash
zig build benchmark-workflow-run
zig build benchmark-workflow-quick
```

What it proves:
- a benchmark-style executable can be modeled as dedicated run targets
- different benchmark sizes can be exposed as different commands

Syntax focus:
- workflow target naming for benchmarks
- argument-specialized run targets

Diagram:

```text
benchmark_workflow_demo
  + arg 750000 -> benchmark-workflow-run
  + arg 100000 -> benchmark-workflow-quick
```

## 15. C++20 Modules

Targets:

```bash
zig build cxx20-modules
zig build cxx20-modules-run
```

What it proves:
- Vex can orchestrate a real C++20 module pipeline
- compiler strategy can be explicit when `zig c++` is not the correct driver

Syntax focus:
- nested compiler orchestration
- explicit `.pcm` and object generation steps
- environment override with `VEX_MODULES_CXX`

Important:
- this example intentionally uses Homebrew LLVM Clang on this machine
- it does not pretend `zig c++` supports the required module flow here

Diagram:

```text
math.cppm --precompile--> math.pcm
math.cppm --compile-----> math.o (with math.pcm)
main.cpp  --link--------> cxx20_modules_demo (with math.o + math.pcm)
```

## 16. WebAssembly: WASI

Targets:

```bash
zig build wasm-wasi
zig build wasm-wasi-report
```

What it proves:
- Vex can emit a `wasm32-wasi-musl` executable artifact
- the output can be validated as a real wasm binary

Syntax focus:
- wasm target selection
- `*-report` semantics for non-native artifacts

Diagram:

```text
main.zig -> wasm_wasi_demo.wasm
wasm-wasi-report -> WebAssembly.validate(...)
```

## 17. WebAssembly: Freestanding Exports

Targets:

```bash
zig build wasm-exports
zig build wasm-exports-run
```

What it proves:
- Vex can emit a freestanding exported wasm module
- host environments can load and call exported functions

Syntax focus:
- freestanding wasm output
- host-side validation through `*-run`

Diagram:

```text
lib.zig -> wasm_exports_demo.wasm
Node.js -> instantiate wasm -> call add / mul_add
```

## 18. WebAssembly: Browser Demo

Targets:

```bash
zig build wasm-web-demo
zig build wasm-web-demo-smoke
zig build wasm-web-demo-serve
```

What it proves:
- the wasm export artifact can be staged into a browser-servable site
- HTML, JS, and `.wasm` are all emitted by the build graph
- local HTTP serving and smoke validation are part of the workflow

Syntax focus:
- staged web assets under `zig-out/www/...`
- `*-serve` and `*-smoke` workflow naming
- wasm artifact plus browser harness in one build

Diagram:

```text
wasm_exports_demo.wasm
index.html
app.js
   |
   v
zig-out/www/wasm-exports/
   |
   +--> wasm-web-demo-smoke
   +--> wasm-web-demo-serve
```

## 19. CMake Interop Examples

Targets:

```bash
zig build cmake-combo-run
zig build cmake-net-run
VEX_SYSTEM_CMDS=1 zig build cmake-shim
```

What they prove:
- CMake-built third-party dependencies can be brought under the Vex graph
- system-command-gated flows can still be modeled explicitly

Syntax focus:
- `VEX_SYSTEM_CMDS=1`
- CMake dependency orchestration inside a Vex-owned graph

Diagram:

```text
Vex graph
  -> clone/configure/build/install CMake deps
  -> link final artifact
  -> run or inspect
```
