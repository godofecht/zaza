# Vex: Modern C++ Build System with Zig

A sophisticated build system that leverages Zig's powerful C++ compilation capabilities to provide a modern alternative to traditional build systems like CMake.

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Installation](#installation)
3. [Tutorial: Building Your First Project](#tutorial-building-your-first-project)
4. [Advanced Usage](#advanced-usage)
5. [Dependency Management](#dependency-management)
6. [Comparison with CMake](#comparison-with-cmake)
7. [Build System Features](#build-system-features)
8. [Examples](#examples)
9. [Examples Guide](#examples-guide)
10. [Syntax Reference](#syntax-reference)
11. [Troubleshooting](#troubleshooting)
12. [Roadmap](#roadmap)
13. [Wiki Website](#wiki-website)

## 🚀 Quick Start

```bash
# Optional: load repo-local cache dirs (recommended)
# Requires direnv: https://direnv.net
direnv allow
```

```bash
# Build (default)
zig build

# Run all tests explicitly
zig build test

# Run the verified example matrix
zig build example-matrix

# Run the mixed Zig + C++ example
zig build run-hello-vex

# Run the package producer/consumer flow
zig build package-consumer-run

# Run the browser-facing wasm smoke test
zig build wasm-web-demo-smoke

# Serve the browser-facing wasm demo
zig build wasm-web-demo-serve
```

```bash
# Enable system commands (git/cmake) when needed
VEX_SYSTEM_CMDS=1 zig build
# (fallback) zig build -Dsystem-cmds=true
```

```bash
# Zero-shell build (no git/cmake). Uses local deps via build.zig.zon.
VEX_SYSTEM_CMDS=0 zig build
# (fallback) zig build -Dsystem-cmds=false
```

## 📦 Installation

### Prerequisites
- **Zig 0.14.0** or later
- **C++17 compatible compiler** (clang, gcc, or msvc)
- **Git** (for dependency fetching)

### Install Zig
```bash
# macOS (using Homebrew)
brew install zig

# Or download directly from ziglang.org
curl -L https://ziglang.org/download/0.14.0/zig-macos-x86_64-0.14.0.tar.xz | tar xJ
```

## 🧭 Wiki Website

A wiki-style documentation site lives in `wiki/` and explains:
- what Vex is,
- current capabilities,
- how to use it clearly,
- and a phased strategy to replace CMake-centric workflows.

Run it locally:

```bash
cd wiki
python3 -m http.server 8000
```

Then open `http://localhost:8000`.

## 📚 Registry (Auto-Fetch)

Vex ships a lightweight registry and **auto-fetches** dependencies into `build.zig.zon`
when you run `zig build`. (Disable with `VEX_REGISTRY=0`.)

```bash
# auto-fetch and pin dependencies from registry/registry.json
zig build
```

```bash
# optional: presets
VEX_PRESET=release zig build
```

```bash
# lockfile (vex.lock) is updated when registry fetch runs
```

```bash
# limit which examples auto-wire into the build
VEX_EXAMPLES=juce zig build
```

## 📦 Install / Export (CMake-style)

Vex can install headers/libs and emit a minimal CMake config for consumers.

```zig
pub var example = cpp.CppExample{
    .name = "hello_vex_cpp",
    .source_files = &.{"src/main.cpp"},
    .install_headers = &.{"include/hello_vex.h"},
    .export_cmake = true,
};
```

This produces:
- `zig-out/include/<name>/...`
- `zig-out/lib/...` (if `install_libs` provided)
- `zig-out/cmake/<name>/<name>Config.cmake`
- `zig-out/share/vex/<name>.json`

## ✅ Verified Surface

The repo now has a single matrix target for the verified example surface:

```bash
zig build example-matrix
```

This runs the currently verified targets sequentially:

- `run-hello-vex`
- `proof-library-run`
- `generated-code-run`
- `package-consumer-run`
- `mixed-stack-run`
- `interface-object-graph-run`
- `test-workflows-run`
- `generated-headers-run`
- `shared-plugin-run`
- `preset-profiles-run`
- `cross-compile-cli-report`
- `resources-bundle-run`
- `bindings-run`
- `benchmark-workflow-run`
- `cxx20-modules-run`
- `wasm-wasi-report`
- `wasm-exports-run`
- `wasm-web-demo-smoke`

## 🧰 Tooling (compile_commands.json)

Vex emits `compile_commands.json` for Zig-built C++ targets and enables
`CMAKE_EXPORT_COMPILE_COMMANDS=ON` for CMake builds.

## 🧩 Generator Expressions (subset)

Vex supports a minimal subset of CMake-style config expressions on list fields:

```
$<CONFIG:Debug>-DDEBUG_ONLY=1
```

These are filtered per build configuration in Zig builds and passed through to CMake unchanged.

## 📚 Tutorial: Building Your First Project

### Step 1: Project Setup

Create a new C++ project with Vex:

```bash
mkdir my_vex_project
cd my_vex_project
# Copy the Vex build system files
cp -r /path/to/vex_zig/-Vex/build .
cp /path/to/vex_zig/-Vex/build.zig .
```

### Step 2: Create Your Source Code

Create `src/main.cpp`:
```cpp
#include <iostream>
#include <nlohmann/json.hpp>

int main() {
    nlohmann::json config = {
        {"app_name", "My Vex Project"},
        {"version", "1.0.0"},
        {"debug", true}
    };
    
    std::cout << "Configuration:\n" << config.dump(4) << std::endl;
    return 0;
}
```

### Step 3: Configure Build System

Create a simple `build.zig`:
```zig
const std = @import("std");
const cpp = @import("build/cpp_example.zig");

pub fn build(b: *std.Build) !void {
    const exe = try cpp.CppExample{
        .name = "my_app",
        .description = "My Vex Application",
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{"deps/json/single_include"},
        .public_defines = &.{"HAS_JSON=1"},
        .cpp_flags = &.{"-D_HAS_EXCEPTIONS=1"},
        .deps = &.{
            .{ .name = "json", .url = "https://github.com/nlohmann/json.git", .type = .Zig },
        },
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = .Zig,
        .main_build_system = .Zig,
        .cpp_std = "17",
    }.build(b);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);
}
```

### Step 4: Build and Run

```bash
# Fetch dependencies and build
zig build --fetch
zig build

# Run your application
zig build run
```

### Step 5: Advanced Configuration

Add multiple build configurations:
```zig
const configs = &.{
    .{ .mode = .Debug, .defines = &.{"DEBUG=1"} },
    .{ .mode = .ReleaseFast, .defines = &.{"NDEBUG=1"} },
    .{ .mode = .ReleaseSafe, .defines = &.{"DEBUG=1", "NDEBUG=1"} },
};
```

## 🔧 Advanced Usage

### Custom C++ Flags
```zig
const cpp_flags = &.{
    "-D_HAS_EXCEPTIONS=1",
    "-Wall",
    "-Wextra",
    "-O2",
};
```

### Multiple Source Files
```zig
.source_files = &.{
    "src/main.cpp",
    "src/utils.cpp",
    "src/config.cpp",
},
```

### System Dependencies
```zig
exe.linkSystemLibrary("pthread", .{});
exe.linkSystemLibrary("ssl", .{});
exe.linkSystemLibrary("crypto", .{});
```

## � Dependency Management

Vex provides automatic dependency management:

### Header-Only Libraries
```zig
.deps = &.{
    .{ 
        .name = "json", 
        .url = "https://github.com/nlohmann/json.git", 
        .include_path = "single_include" 
    },
},
```

### Compiled Libraries
```zig
.deps = &.{
    .{ 
        .name = "fmt", 
        .url = "https://github.com/fmtlib/fmt.git", 
        .type = .CMake 
    },
},
```

### Local Dependencies
```zig
.include_dirs = &.{
    "deps/json/single_include",
    "external/my_lib/include",
},
```

## ⚔️ Comparison with CMake

| Feature | Vex (Zig) | CMake |
|---------|-----------|-------|
| **Learning Curve** | Low (Zig language) | High (CMake syntax) |
| **Performance** | Fast (native Zig) | Slower (interpreted) |
| **Dependency Management** | Built-in Git fetching | External (FetchContent, Conan) |
| **Cross-Compilation** | First-class support | Complex configuration |
| **Language Integration** | Native C++ support | Generator-based |
| **Build Times** | Fast (incremental) | Slower (regeneration) |
| **IDE Support** | Growing | Mature |
| **Ecosystem** | Growing | Extensive |

### Advantages of Vex over CMake

1. **Unified Language**: Build scripts written in Zig, not CMake's custom language
2. **Better Performance**: Native compilation vs. interpreted scripts
3. **Modern Dependency Management**: Git-based fetching with version control
4. **Simpler Syntax**: More readable and maintainable build configurations
5. **Better Error Messages**: Clear, actionable error reporting
6. **Cross-Platform**: Truly cross-compilation ready

### When to Use CMake Instead

- **Legacy Projects**: Existing CMake-based codebases
- **IDE Integration**: Better support in some IDEs
- **Complex Dependencies**: Some third-party libraries only provide CMake
- **Team Expertise**: Team already familiar with CMake

## �️ Build System Features

### Automatic Dependency Management
```zig
.deps = &.{
    .{ .name = "json", .url = "https://github.com/nlohmann/json.git" },
},
```

### Cross-Platform Compilation
```zig
const target = b.standardTargetOptions(.{});
const mode = b.standardReleaseOptions();
```

### Incremental Builds
```bash
zig build
```

### Fast Build Times
```bash
zig build --fetch
```

### Clear Error Messages
```bash
zig build --verbose
```

### Native C++ Support
```cpp
#include <iostream>
#include <nlohmann/json.hpp>
```

### Unified Language
```zig
const std = @import("std");
const cpp = @import("build/cpp_example.zig");
```

## 🧭 Replacing CMake (Mental Model)

Here is how Vex maps common CMake concepts to Zig build code:

- `CMakeLists.txt` -> `build.zig`
- `add_executable()` -> `b.addExecutable(...)` or `CppExample.build(...)`
- `target_include_directories()` -> `exe.addIncludePath(...)`
- `target_compile_options()` -> `CppExample.cpp_flags`
- `FetchContent` / `ExternalProject` -> `Dependency` with `.url` + optional `VEX_SYSTEM_CMDS=1`
- `cmake --build` -> `zig build`

## 🔀 Mixed Zig + CMake

You can build Zig targets and C++ targets in one `build.zig`, and selectively run CMake for deps that only ship CMake.

Example (from `examples/hello_vex`):
- `hello_vex_zig` is a pure Zig executable.
- `hello_vex_cpp` is a C++ executable built via Vex.

Run it:

```bash
zig build hello-vex
zig build run-hello-vex
```

For CMake-based dependencies (shim):

```bash
VEX_SYSTEM_CMDS=1 zig build cmake-shim
```

## 📦 Zig Package Manager (No System Commands)

This repo uses `build.zig.zon` for dependencies and ships a vendored copy of
`nlohmann/json` in `deps/json`. This means `zig build` works **without** running
`git` or `cmake`.

If you want to switch to remote fetches, replace the `.path` entry in
`build.zig.zon` with a `.url` + `.hash` (see Zig's package manager docs), then
run `zig fetch` once to populate the hash.

## 📝 Examples

Detailed per-example explanations and diagrams live in
[`docs/EXAMPLES.md`](/Users/abhishekshivakumar/vex_zig/-Vex/docs/EXAMPLES.md).

### Hello Vex (Zig + C++)
```bash
zig build hello-vex
zig build run-hello-vex
```

### Package Producer / Consumer
```bash
zig build package-producer-run
zig build package-consumer-run
```

### Mixed C + C++ + Zig
```bash
zig build mixed-stack-run
```

### Interface / Object / Static Graph
```bash
zig build interface-object-graph-run
```

### Workflow Modes (args + env + cwd)
```bash
zig build test-workflows-run
zig build test-workflows-unit
zig build test-workflows-integration
```

### Generated Source
```bash
zig build generated-code-run
```

### Generated Header
```bash
zig build generated-headers-run
```

### Shared Plugin
```bash
zig build shared-plugin-run
```

### Preset Profiles
```bash
zig build preset-profiles-run
VEX_PRESET=asan zig build preset-profiles-run
VEX_PRESET=lto zig build preset-profiles-run
```

Notes:
- On this machine, `asan` is blocked by missing sanitizer runtime support.
- On this machine, `lto` is blocked unless the toolchain is using LLD.

### Cross-Compile CLI
```bash
zig build cross-compile-cli
zig build cross-compile-cli-report
```

### CMake Combo (fmt + spdlog)
```bash
zig build cmake-combo
zig build cmake-combo-run
```

### CMake Net (curl + zlib + mbedtls)
```bash
zig build cmake-net
zig build cmake-net-run
```

### CMake Shim (mixed Zig + CMake)
```bash
VEX_SYSTEM_CMDS=1 zig build cmake-shim
```

### Proof Library
```bash
zig build proof-library
zig build proof-library-run
```

### Resources Bundle
```bash
zig build resources-bundle-run
```

### Zig <-> C++ Bindings
```bash
zig build bindings-run
```

### Benchmark Workflow
```bash
zig build benchmark-workflow-run
zig build benchmark-workflow-quick
```

### JUCE (versioned)
```bash
# JUCE 7.x via FetchContent
JUCE_GIT_TAG=7.0.9 VEX_EXAMPLES=juce zig build juce
```

### C++20 Modules
```bash
zig build cxx20-modules-run
```

The modules example intentionally uses Homebrew LLVM Clang on this machine rather
than `zig c++`, because the local `zig c++` driver does not currently expose a
working C++20 modules flow here.

### WebAssembly
```bash
zig build wasm-wasi-report
zig build wasm-exports-run
zig build wasm-web-demo
zig build wasm-web-demo-smoke
zig build wasm-web-demo-serve
```

`wasm-web-demo-serve` serves the staged browser demo at
`http://127.0.0.1:8000`.

## 📚 Examples Guide

See [`docs/EXAMPLES.md`](/Users/abhishekshivakumar/vex_zig/-Vex/docs/EXAMPLES.md).

## 🔤 Syntax Reference

See [`docs/SYNTAX_REFERENCE.md`](/Users/abhishekshivakumar/vex_zig/-Vex/docs/SYNTAX_REFERENCE.md).

## 🤔 Troubleshooting

### Common Issues
- **Missing dependencies**: Run `zig build --fetch` to fetch dependencies
- **Build errors**: Check error messages for clues, or run `zig build --verbose` for more information
- **Runtime errors**: Check your code for bugs, or run your application with a debugger

### Getting Help
- **Vex documentation**: Check the Vex documentation for more information on build system features and usage
- **Zig documentation**: Check the Zig documentation for more information on the Zig language and standard library
- **Community support**: Join the Vex community for help and support from other users

### JUCE on Windows
See `docs/JUCE_WINDOWS.md` for Zig 0.14 workarounds.

## 🛣 Roadmap

See `docs/ROADMAP.md`.
