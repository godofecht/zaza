# Vex Syntax Reference

This is the practical syntax and command reference for the current repo.

It documents:
- target naming conventions
- command naming conventions
- important environment variables
- current `CppExample` fields that matter most in day-to-day use
- when to use build targets vs run/report/serve targets

This is a reference for the current surface, not a promise of a final stable API.

## 1. Command Shape

Current conventions:

```text
zig build <target>
```

Target naming:

- `<name>`: build or stage an artifact
- `<name>-run`: execute an artifact
- `<name>-report`: inspect or validate an artifact
- `<name>-serve`: start a local server
- `example-matrix`: run the verified example surface sequentially

Examples:

```bash
zig build hello-vex
zig build run-hello-vex
zig build cross-compile-cli-report
zig build wasm-web-demo-serve
```

## 2. Environment Variables

### `VEX_EXAMPLES`

Limits which examples wire into the root graph.

```bash
VEX_EXAMPLES=juce zig build
VEX_EXAMPLES=package-consumer,wasm-exports zig build example-matrix
```

### `VEX_SYSTEM_CMDS`

Enables build steps that depend on external tools like `git` and `cmake`.

```bash
VEX_SYSTEM_CMDS=1 zig build cmake-shim
```

### `VEX_PRESET`

Applies a named preset to examples that opt into preset configs.

```bash
VEX_PRESET=debug zig build preset-profiles-run
VEX_PRESET=release zig build
VEX_PRESET=asan zig build preset-profiles-run
VEX_PRESET=lto zig build preset-profiles-run
```

### `VEX_TARGET`

Overrides the root target triple for the main build graph.

```bash
VEX_TARGET=x86_64-windows-gnu zig build
VEX_TARGET=aarch64-linux-musl zig build
```

### `VEX_WINDOWS_TOOLCHAIN`

Special-case selector for Windows target behavior.

```bash
VEX_WINDOWS_TOOLCHAIN=gnu zig build
```

### `VEX_REGISTRY`

Turns registry-driven dependency mutation on or off.

```bash
VEX_REGISTRY=0 zig build
```

### `VEX_MODULES_CXX`

Overrides the compiler used by the C++20 modules example.

```bash
VEX_MODULES_CXX=/path/to/clang++ zig build cxx20-modules-run
```

## 3. Root Build Targets

Important top-level targets:

- `all`: tests + default artifacts + optional CMake shim flow
- `test`: all test targets
- `example-matrix`: verified example surface
- `run-cpp`: ad hoc single-file C++ execution
- `run-zig`: ad hoc single-file Zig execution
- `vex-fetch`: registry fetch helper

Examples:

```bash
zig build test
zig build example-matrix
zig build run-cpp -- examples/hello_vex/src/main.cpp
zig build run-zig -- examples/hello_vex/src/main.zig
zig build vex-fetch -- fmt
```

## 4. `CppExample` Mental Model

The current repo still relies heavily on `CppExample`.

Typical shape:

```zig
pub var example = cpp.CppExample{
    .name = "my_app",
    .description = "demo",
    .kind = .executable,
    .source_files = &.{"src/main.cpp"},
    .include_dirs = &.{},
    .public_include_dirs = &.{"include"},
    .cpp_flags = &.{"-Wall"},
    .public_defines = &.{"MY_API=1"},
    .public_link_libs = &.{"pthread"},
    .deps = &.{},
    .configs = &.{.{ .mode = .Debug }},
    .deps_build_system = .Zig,
    .main_build_system = .Zig,
    .cpp_std = "17",
};
```

## 5. `CppExample` Fields

### Identity

- `.name`: target base name
- `.description`: human-facing explanation
- `.kind`: one of:
  - `.executable`
  - `.static_library`
  - `.shared_library`
  - `.object_library`
  - `.interface_library`

### Sources

- `.source_files`: normal C/C++ sources
- `.generated_source_files`: generated sources that should also be compiled
- `.custom_commands`: pre-build command steps that produce generated inputs

Pattern:

```zig
.generated_source_files = &.{"zig-out/gen/generated.cpp"},
.custom_commands = &.{
    .{
        .name = "generate_generated_cpp",
        .argv = &.{"sh", "scripts/generate.sh", "zig-out/gen/generated.cpp"},
    },
},
```

### Include Directories

- `.include_dirs`: private/general include dirs
- `.public_include_dirs`: include dirs intended for downstream use
- `.private_include_dirs`: explicit private include dirs

### Compile Flags / Defines

- `.cpp_flags`: raw compile flags
- `.public_defines`: exported preprocessor defines
- `.private_defines`: local-only defines

### Linking

- `.public_link_libs`: system libraries propagated outward
- `.private_link_libs`: local-only system libraries
- per-config fields inside `BuildConfig` can also add:
  - `.link_paths`
  - `.link_libs`
  - `.link_files`
  - `.link_frameworks`

### Install / Export

- `.install_headers`
- `.install_libs`
- `.export_cmake`
- `.export_name`

These produce things like:

```text
zig-out/include/<export_name>/...
zig-out/lib/...
zig-out/cmake/<export_name>/<export_name>Config.cmake
zig-out/share/vex/<export_name>.json
```

### Dependencies

- `.deps`: git/CMake/Zig package dependencies
- `.deps_build_system`: how dependencies should be built
- `.main_build_system`: how the main target should be built

## 6. `BuildConfig` Reference

Common fields:

- `.mode`
  - `.Debug`
  - `.Release`
  - `.RelWithDebInfo`
  - `.MinSizeRel`
- `.defines`
- `.cpp_flags`
- `.system_includes`
- `.link_paths`
- `.link_libs`
- `.link_files`
- `.link_frameworks`
- `.want_lto`

Example:

```zig
.configs = &.{
    .{
        .mode = .Debug,
        .defines = &.{"DEBUG=1"},
    },
    .{
        .mode = .Release,
        .want_lto = true,
        .defines = &.{"NDEBUG=1", "VEX_LTO=1"},
    },
},
```

## 7. Nested Build Targets

Some examples are intentionally modeled as nested builds because they represent
real downstream or alternate-toolchain flows:

- `package-consumer`
- `cross-compile-cli`
- `cxx20-modules`

Mental model:

```text
root build.zig
  -> invokes ./zig build --build-file <other build.zig> <target>
  -> treats that nested build as part of the top-level workflow
```

## 8. Wasm Command Semantics

Current wasm-specific targets:

- `wasm-wasi`
- `wasm-wasi-report`
- `wasm-exports`
- `wasm-exports-run`
- `wasm-web-demo`
- `wasm-web-demo-smoke`
- `wasm-web-demo-serve`

Interpretation:

- `wasm-wasi`: build a WASI module
- `wasm-wasi-report`: validate the emitted `.wasm`
- `wasm-exports`: build a freestanding exported wasm module
- `wasm-exports-run`: load the module in Node and call its exports
- `wasm-web-demo`: stage the browser demo files
- `wasm-web-demo-smoke`: fetch the staged files over HTTP
- `wasm-web-demo-serve`: serve the staged site locally

## 9. Syntax Goals

The repo is aiming for these syntax rules:

- command names should describe workflow, not implementation detail
- `run` means execute something real
- `report` means inspect/validate without pretending execution is the point
- `serve` means long-running local hosting
- nested builds should be explicit when they model real project boundaries
- environment variables should be short, grep-friendly, and scoped under `VEX_`

## 10. Current Limitations

Important current realities:

- the root graph is pragmatic, not yet a polished final API
- examples still prove capability faster than the first-class API does
- some flows are environment-sensitive:
  - `asan` depends on sanitizer runtime availability
  - `lto` depends on linker/toolchain configuration
  - C++20 modules currently use an explicit LLVM Clang path on this machine

That is why the docs prefer concrete command references and verified examples
over pretending the higher-level API is already fully stabilized.
