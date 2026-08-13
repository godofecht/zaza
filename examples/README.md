# Zaza Examples

Every directory here has its own `README.md` covering what it demonstrates, what
it needs, and the exact command to build and run it.

`ZAZA_EXAMPLES` restricts which examples are wired into the root build graph.
Setting it to a single example keeps configure time short and stops Zaza from
resolving dependencies you do not need. Every command below is written that way.
Dropping the prefix also works, at the cost of configuring the whole graph.

To run the whole verified surface in one command:

```bash
zig build example-matrix
```

That target shells out to `./zig` for each step. See [`setup.sh`](../setup.sh).

## Index

| Example | Command | Demonstrates |
| --- | --- | --- |
| [bench_suite](bench_suite) | `ZAZA_EXAMPLES=bench-suite zig build bench-suite-run` | A benchmark declared through the `addBench` API |
| [benchmark_workflow](benchmark_workflow) | `ZAZA_EXAMPLES=benchmark-workflow zig build benchmark-workflow-run` | A benchmark exposed as size-specific run targets |
| [bindings](bindings) | `ZAZA_EXAMPLES=bindings zig build bindings-run` | Zig calling C++ across a C ABI wrapper |
| [cmake](cmake) | (none) | Unwired early experiment, kept for reference |
| [cmake_combo](cmake_combo) | `ZAZA_EXAMPLES=cmake-combo zig build cmake-combo-run` | fmt + spdlog built by CMake, linked by Zig |
| [cmake_consumer](cmake_consumer) | `sh examples/cmake_consumer/verify.sh` | A plain CMake project consuming a Zaza-built library via `find_package` |
| [cmake_net](cmake_net) | `ZAZA_EXAMPLES=cmake-net zig build cmake-net-run` | curl + zlib + mbedtls with an ordering constraint |
| [cmake_shim](cmake_shim) | `ZAZA_EXAMPLES=cmake-shim ZAZA_SYSTEM_CMDS=1 zig build cmake-shim-run` | The smallest complete CMake interop path |
| [cmake_subdir](cmake_subdir) | `ZAZA_EXAMPLES=cmake-subdir zig build cmake-subdir-run` | Building an in-tree CMake subtree and linking it into a Zaza target |
| [cross_compile_cli](cross_compile_cli) | `ZAZA_EXAMPLES=cross-compile-cli zig build cross-compile-cli-report` | Nested build for a non-host triple |
| [cxx20_modules](cxx20_modules) | `ZAZA_EXAMPLES=cxx20-modules zig build cxx20-modules-run` | A C++20 named-module pipeline |
| [find_package](find_package) | `ZAZA_EXAMPLES=find-package zig build find-package` | Linking an installed library resolved by pkg-config and CMake `find_package` |
| [generated_code](generated_code) | `ZAZA_EXAMPLES=generated-code zig build generated-code-run` | A custom command generating a `.cpp` |
| [generated_headers](generated_headers) | `ZAZA_EXAMPLES=generated-headers zig build generated-headers-run` | A custom command generating a header |
| [hello_zaza](hello_zaza) | `ZAZA_EXAMPLES=hello-zaza zig build run-hello-zaza` | A Zig exe and a C++ exe in one graph |
| [interface_object_graph](interface_object_graph) | `ZAZA_EXAMPLES=interface-object-graph zig build interface-object-graph-run` | Object library folded into a static library |
| [json](json) | `ZAZA_EXAMPLES=json zig build run` | nlohmann/json as a Zig package dependency |
| [juce](juce) | `ZAZA_EXAMPLES=juce ZAZA_SYSTEM_CMDS=1 zig build juce` | A JUCE GUI app through JUCE's CMake integration |
| [mixed_stack](mixed_stack) | `ZAZA_EXAMPLES=mixed-stack zig build mixed-stack-run` | C library, C++ bridge, Zig executable |
| [orchestration](orchestration) | `ZAZA_EXAMPLES=orchestration zig build orchestration-run` | A generator-expressioned define, a `target_link_options` linker option, and a phony target |
| [package_consumer](package_consumer) | `ZAZA_EXAMPLES=package-consumer zig build package-consumer-run` | Consuming an installed package from its manifest |
| [package_producer](package_producer) | `ZAZA_EXAMPLES=package-producer zig build package-producer-run` | Publishing headers, an archive, and a manifest |
| [preset_profiles](preset_profiles) | `ZAZA_EXAMPLES=preset-profiles zig build preset-profiles-run` | `ZAZA_PRESET` selecting a build configuration |
| [proof_library](proof_library) | `ZAZA_EXAMPLES=proof-library zig build proof-library-run` | A plain static library with install/export metadata |
| [resources_bundle](resources_bundle) | `ZAZA_EXAMPLES=resources-bundle zig build resources-bundle-run` | A runtime asset staged into `zig-out/share` |
| [rust_interop](rust_interop) | `ZAZA_EXAMPLES=rust-interop zig build rust-interop-run` | A Cargo staticlib linked into a Zig executable |
| [shared_plugin](shared_plugin) | `ZAZA_EXAMPLES=shared-plugin zig build shared-plugin-run` | A shared library loaded at runtime via `dlopen` |
| [test_workflows](test_workflows) | `ZAZA_EXAMPLES=test-workflows zig build test-workflows-run` | Run modes differing by arg, env, and cwd, via the `addTest` API |
| [unity_build](unity_build) | `ZAZA_EXAMPLES=unity-build zig build unity-build-run` | Several sources compiled as one translation unit (`CMAKE_UNITY_BUILD`) |
| [universal_binary](universal_binary) | `ZAZA_EXAMPLES=universal-binary zig build universal-binary-report` | A macOS universal binary combined from x86_64 and arm64 slices with zaza-lipo |
| [wasm_exports](wasm_exports) | `ZAZA_EXAMPLES=wasm-exports zig build wasm-exports-run` | A freestanding wasm module with exports |
| [wasm_wasi](wasm_wasi) | `ZAZA_EXAMPLES=wasm-wasi zig build wasm-wasi-report` | A `wasm32-wasi-musl` executable, validated |
| [zaza-juce](zaza-juce) | `ZAZA_EXAMPLES=zaza-juce ZAZA_SYSTEM_CMDS=1 zig build zaza-juce` | A JUCE audio app with the audio modules on |
| [zaza_subproject](zaza_subproject) | `ZAZA_EXAMPLES=zaza-subproject zig build zaza-subproject-run` | A Zaza subproject with its own `build.zig`, composed into a parent build |

## Grouped by what you are looking for

**Start here**

`hello_zaza`, `proof_library`, `mixed_stack`.

**Generated code**

`generated_code`, `generated_headers`.

**Packaging and consumption**

`package_producer`, `package_consumer`.

**Target graph shapes**

`interface_object_graph`, `shared_plugin`, `resources_bundle`,
`zaza_subproject` (a subproject with its own `build.zig`), `unity_build`
(sources as one translation unit).

**Other languages**

`bindings` (C++ from Zig), `rust_interop` (Rust from Zig).

**CMake interop**

`cmake_shim`, `cmake_combo`, `cmake_net`, `juce`, `zaza-juce`.

**WebAssembly**

`wasm_wasi`, `wasm_exports`.

**Configuration and workflow**

`preset_profiles`, `test_workflows`, `bench_suite`, `benchmark_workflow`,
`cross_compile_cli`, `orchestration` (generator expressions, link options, a
phony target).

## Optional tools

Most examples need nothing beyond Zig. These are the exceptions:

| Tool | Needed by |
| --- | --- |
| `cmake` + `git` | `cmake_shim`, `cmake_combo`, `cmake_net`, `juce`, `zaza-juce` |
| `cargo` | `rust_interop` |
| `node` | `wasm_wasi`, `wasm_exports` |
| `clang++` with C++20 modules | `cxx20_modules` |
| `file(1)` | `cross_compile_cli` report target |
| `./zig` wrapper | `package_consumer`, `cross_compile_cli`, `rust_interop`, `example-matrix` |

[`setup.sh`](../setup.sh) checks all of these and tells you which examples are
unavailable on your machine.

## Which targets exist

```bash
zig build --list-steps
```

## Further reading

- [Zaza wiki](../docs/WIKI.md). The single-page overview.
- [Examples guide](../docs/EXAMPLES.md). Per-example diagrams and syntax focus.
- [Syntax reference](../docs/SYNTAX_REFERENCE.md). The full field and command surface.
