# Zaza

A build system for C, C++, Zig, Rust, and WebAssembly that uses Zig's build
graph as its control plane. There is no separate build DSL. Build files are Zig
programs.

Source: [github.com/godofecht/zaza](https://github.com/godofecht/zaza)

---

## Contents

- [What Zaza is](#what-zaza-is)
- [Compared to CMake](#compared-to-cmake)
- [Installation](#installation)
- [Five-minute quickstart](#five-minute-quickstart)
- [Core concepts](#core-concepts)
- [Environment variables](#environment-variables)
- [The example matrix](#the-example-matrix)
- [WebAssembly](#webassembly)
- [Fast rebuilds](#fast-rebuilds)
- [Testing and benchmarks](#testing-and-benchmarks)
- [Troubleshooting](#troubleshooting)
- [Where to go next](#where-to-go-next)

---

## What Zaza is

Starting a new native project usually means writing CMake. That buys you a
second language, a second mental model, and a configure step that has to be
debugged separately from the code. Cross-compilation and mixed-language work sit
on top of that as further layers.

Zig already ships a build system with a dependency graph, content-addressed
caching, a C and C++ compiler, and cross-compilation to every target it
supports. What it does not ship is the higher-level vocabulary that C++ projects
expect: usage requirements, install and export rules, package manifests,
generated-source pipelines, preset profiles, and a path for depending on
libraries that only build with CMake.

Zaza is that layer. A `build.zig` declares targets in Zig, and Zaza turns them
into `std.Build` steps.

```zig
const std = @import("std");
const cpp = @import("build_lib/cpp_example.zig");

pub fn build(b: *std.Build) !void {
    const exe = try cpp.CppExample.executable(.{
        .name = "my_app",
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{"include"},
        .public_defines = &.{"MY_APP=1"},
        .cpp_std = "17",
    }).build(b);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run my_app");
    run_step.dependOn(&run_cmd.step);
}
```

**What this gets you**

- C, C++, Zig, and Rust targets in one graph, linked to each other.
- Cross-compilation with a target triple and no toolchain file.
- CMake-only dependencies cloned, configured, built, and installed by the graph.
- Install and export output that a separate downstream project can consume.
- WebAssembly targets, both WASI and freestanding, in the same build file.

**What it does not get you**

Zaza is example-driven and its public API is not settled. The higher-level
target model is still `CppExample` rather than a first-class library type. See
[`ROADMAP.md`](ROADMAP.md) for what is being built next.

---

## Compared to CMake

The goal is coverage of the workflows people actually use, rather than
one-for-one syntax compatibility.

| CMake | Zaza |
| --- | --- |
| `CMakeLists.txt` | `build.zig` |
| `add_executable()` | `CppExample.executable(...)` |
| `add_library(STATIC ...)` | `CppExample.staticLibrary(...)` |
| `add_library(SHARED ...)` | `CppExample.sharedLibrary(...)` |
| `target_include_directories(PUBLIC ...)` | `.public_include_dirs` |
| `target_compile_definitions(PRIVATE ...)` | `.private_defines` |
| `target_link_options(...)` | `.link_options` (typed `LinkOption`) |
| `add_custom_command()` | `.custom_commands` + `.generated_source_files` |
| `add_custom_command(TARGET ... POST_BUILD copy ...)` | `.artifact_copies`, `.file_copies`, and copy helpers |
| `add_custom_target()` | `zaza.addPhonyTarget(...)` |
| `install()` / `export()` | `.install_headers`, `.export_cmake`, `.export_name` |
| `find_package()` (consume) | `zaza.findPackage(...)` via pkg-config or CMake |
| `find_package()` (produce) | `.export_cmake` installs an imported-target package |
| `add_subdirectory()` (CMake) | `zaza.addCMakeSubdirectory(...)` |
| `add_subdirectory()` (Zaza) | `zaza.defineSubproject(...)` |
| generator expressions | evaluated in flags and defines; `zaza.evalGenex` |
| `CMAKE_UNITY_BUILD` | `.unity_build` |
| `FetchContent` | registry entry resolved into `build.zig.zon` + `zaza.lock` |
| `CMakePresets.json` | `ZAZA_PRESET` |
| toolchain file | a target triple |

[`CMAKE_PARITY.md`](CMAKE_PARITY.md) is the honest version: a tiered feature
plan with a status column marking each concept as partial, missing, or done, and
an explicit list of what to avoid building before the core target model is
solid. Read it before betting a project on Zaza.

The short summary of that document: executable and library targets, install and
export, dependency fetching with a verified lock, custom commands, transitive
usage requirements, object and interface libraries, `find_package` in both
directions, `add_subdirectory` for CMake and Zaza subtrees, target link options,
generator expressions, and unity builds all work today and have examples. The
concrete feature-mapping table has no partial rows left. What remains is the
Tier 2/3 polish: precompiled headers, ccache integration, alias targets,
`compile_commands.json` import, and editor tooling.

---

## Installation

### Prerequisites

**Required**

- [Zig](https://ziglang.org/download/) 0.14.1, 0.15.2 or 0.16.0. All three are
  tested in CI and verified against the full test suite.

**Optional**

Most examples need nothing else. These are the exceptions:

| Tool | Used by |
| --- | --- |
| `cmake` and `git` | The CMake interop and JUCE examples |
| `cargo` | The Rust interop example |
| `node` | The WebAssembly validation and export examples |
| A `clang++` with C++20 module support | The C++20 modules example |

### Setup

```bash
git clone https://github.com/godofecht/zaza.git
cd zaza
./setup.sh
```

`setup.sh` reports your Zig version, warns if it is outside the tested range,
creates the machine-local `./zig` wrapper if it is missing, lists which optional
examples your machine cannot run, and then runs the test suite. It is safe to
run repeatedly.

Real output on a machine with everything installed:

```text
Toolchain
  ok  zig 0.15.2 (/opt/homebrew/bin/zig)

Wrapper
  ok  ./zig wrapper present

Optional tools
  ok  git - git version 2.50.1 (Apple Git-155)
  ok  cmake - cmake version 4.3.3
  ok  cargo - cargo 1.92.0 (344c4567c 2025-10-21)
  ok  node - v25.5.0
  ok  file - present
  ok  clang++ with modules - /opt/homebrew/opt/llvm/bin/clang++

Examples
  ok  every example is available on this machine

Tests
ZAZA_EXAMPLES=none zig build test --summary all

Build Summary: 43/43 steps succeeded; 87/87 tests passed
```

And on a machine missing several of the optional tools:

```text
Optional tools
  ok  git - git version 2.50.1 (Apple Git-155)
warn  cmake not found
warn  cargo not found
warn  node not found
  ok  file - present
warn  no clang++ with C++20 module support at /nope/clang++

Unavailable without the tools above
  cmake_shim, cmake_combo, cmake_net, juce, zaza-juce (needs cmake)
  rust_interop (needs cargo)
  wasm_wasi, wasm_exports (needs node)
  cxx20_modules (set ZAZA_MODULES_CXX to a clang++ that supports C++20 modules)

Everything else runs with Zig alone.
```

### The `./zig` wrapper

Several targets shell out to a sibling build file, and they invoke `./zig` by
name rather than a bare `zig`. The wrapper pins both Zig cache directories to
the repo root, which is what those nested builds expect. It hardcodes one
machine's paths, so it is gitignored and absent from a fresh clone.

`setup.sh` creates it. Without it, `package-consumer`, `cross-compile-cli`,
`rust-interop`, and `example-matrix` fail with exit code 127.

---

## Five-minute quickstart

### 1. Run the test suite

```bash
ZAZA_EXAMPLES=none zig build test --summary all
```

```text
Build Summary: 43/43 steps succeeded; 87/87 tests passed
```

`ZAZA_EXAMPLES=none` keeps the C++ examples out of the graph. Zig resolves every
declared dependency while the graph is constructed, so leaving them on would
fetch JUCE, curl, mbedtls, zlib, spdlog, and fmt just to run Zig tests.

### 2. Run the smallest example

```bash
ZAZA_EXAMPLES=hello-zaza zig build run-hello-zaza
```

```text
=== RUN: hello_zaza_cpp ===
lang: cpp
msg: hello from zig build system

=== RUN: hello_zaza_zig ===
lang: zig
msg: hello_zaza (zig)
```

One Zig executable and one C++ executable, both in the same graph, both run by
one step.

### 3. See what else exists

```bash
zig build --list-steps
```

With `ZAZA_EXAMPLES=none` that is a short list:

```text
  install                      Copy build artifacts to prefix path
  uninstall                    Remove build artifacts from prefix path
  hello-zaza                   Build hello_zaza (Zig + C++ via Zaza)
  run-hello-zaza               Run both hello_zaza executables
  test                         Run all tests
  example-matrix               Run the verified example matrix sequentially
  all (default)                Run all tests, build default artifacts, and optionally run CMake shim
  run-cpp                      Compile and run a single C++ file (usage: zig build run-cpp -- path/to/file.cpp)
  run-zig                      Compile and run a single Zig file (usage: zig build run-zig -- path/to/file.zig)
  zaza-fetch                   Fetch a dependency into build.zig.zon (usage: zig build zaza-fetch -- <name>)
```

Without it, every example registers its own targets, for 61 steps in total.

### 4. Cross-compile something

```bash
ZAZA_EXAMPLES=cross-compile-cli zig build cross-compile-cli-report
```

```text
examples/cross_compile_cli/zig-out/bin/cross_compile_cli: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, with debug_info, not stripped
```

A statically linked Linux binary, produced on macOS, with no cross-toolchain
installed.

### 5. Build and consume a package

```bash
ZAZA_EXAMPLES=package-consumer zig build package-consumer-run
```

```text
package consumer result: 42
```

That one command installs the producer library, writes its manifest, then runs a
separate build file that reads the manifest and links against the result.

### 6. Compile and run a single file

```bash
zig build run-cpp -- src/simple_example.cpp
```

```text
=== RUN: cpp ===
src: src/simple_example.cpp\nout: zig-out/bin/run_cpp\nflags: (none)
Hello from Zaza C++ example!
This is a simple test to verify Zig 0.14.0 works with C++
Build system is working!
```

Extra compiler flags go after the source path:

```bash
zig build run-cpp -- src/simple_example.cpp -O2
```

There is a Zig equivalent:

```bash
zig build run-zig -- examples/cross_compile_cli/src/main.zig
```

```text
cross target: aarch64-macos
```

---

## Core concepts

### The build graph

A Zaza build file is a Zig program that adds steps to `std.Build`. Zig runs it,
resolves the dependency graph, and executes only the steps whose inputs changed.
There is no configure phase distinct from the build phase, and no generated
Makefiles or Ninja files in between.

Step names follow four conventions:

| Pattern | Meaning |
| --- | --- |
| `<name>` | Build or stage the artifact |
| `<name>-run` | Execute something real |
| `<name>-report` | Inspect or validate an artifact the host cannot run |
| `<name>-serve` | Start a long-running local server |

`build_lib/build_graph.zig` holds a small standalone graph structure with
topological sort, used by the tests to assert ordering behaviour independently
of `std.Build`.

### `CppExample`

`CppExample` is the C and C++ target type. It is a plain struct, so a target is
data that can be inspected, serialised, and modified before it is built.

```zig
pub var example = cpp.CppExample.executable(.{
    .name = "my_app",
    .description = "demo",
    .source_files = &.{"src/main.cpp"},
    .public_include_dirs = &.{"include"},
    .public_defines = &.{"MY_API=1"},
    .public_link_libs = &.{"pthread"},
    .cpp_std = "17",
});
```

Five constructors cover the target kinds:

```zig
cpp.CppExample.executable(...)
cpp.CppExample.staticLibrary(...)
cpp.CppExample.sharedLibrary(...)
cpp.CppExample.objectLibrary(...)
cpp.CppExample.interfaceLibrary(...)
```

All five call `CppExample.make(kind, options)`.

Fields split along the usual visibility lines. `public_include_dirs`,
`public_defines`, and `public_link_libs` are meant to propagate to consumers.
`private_include_dirs`, `private_defines`, and `private_link_libs` are not.
Transitive propagation across dependency edges is partial today; see
[`CMAKE_PARITY.md`](CMAKE_PARITY.md).

Generated sources are declared alongside a command that produces them:

```zig
.generated_source_files = &.{"zig-out/gen/generated.cpp"},
.custom_commands = &.{
    .{
        .name = "generate_generated_cpp",
        .argv = &.{"sh", "scripts/generate.sh", "zig-out/gen/generated.cpp"},
    },
},
```

Install and export fields produce a stable layout:

```text
zig-out/include/<export_name>/...
zig-out/lib/...
zig-out/cmake/<export_name>/<export_name>Config.cmake
zig-out/share/zaza/<export_name>.json
```

Artifact copies stage a built output in extra install-style directories without
shelling out to `cp`:

```zig
.artifact_copies = &.{
    .{ .dest_dir = "share/my_host/plugins" },
},
```

Use `zaza.addArtifactCopies` when a build file hand-builds the artifact with
plain `std.Build` calls. The shared plugin example uses that lower-level helper
to copy the dynamic library into `zig-out/share/shared_plugin/plugins/` before
the host loads it.

File copies stage runtime assets and other non-code files the same way:

```zig
.file_copies = &.{
    .{
        .source_path = "assets/message.txt",
        .dest_path = "share/my_app/message.txt",
    },
},
```

Use `zaza.addFileCopies` when a build file assembles the executable manually.
The resources bundle example uses it to copy
`examples/resources_bundle/assets/message.txt` into
`zig-out/share/resources_bundle/message.txt` before the run step reads it.

The full field list is in [`SYNTAX_REFERENCE.md`](SYNTAX_REFERENCE.md).

### Presets

`ZAZA_PRESET` selects a named `BuildConfig` list from `build_lib/presets.zig`.
Six are defined:

| Preset | Effect |
| --- | --- |
| `debug` | `mode = .Debug` (the default) |
| `release` | `mode = .Release` |
| `relwithdebinfo` | `mode = .RelWithDebInfo` |
| `minsizerel` | `mode = .MinSizeRel` |
| `asan` | `.Debug` plus `-fsanitize=address` and `ZAZA_ASAN=1` |
| `lto` | `.Release` plus `want_lto` and `ZAZA_LTO=1` |

An unrecognised name silently falls back to `debug`.

```bash
ZAZA_EXAMPLES=preset-profiles ZAZA_PRESET=release zig build preset-profiles-run
```

```text
preset: release
preset runtime ready
```

Presets apply only to the examples that opt in: `cmake_combo`, `cmake_net`,
`cmake_shim`, and `preset_profiles`.

### The package registry

`registry/registry.json` maps a short package name to a source URL and version.

```bash
zig run scripts/zaza.zig -- list
```

```text
Available packages (7):
                  juce 7.0.9
                   fmt 10.2.1
                spdlog 1.14.1
                  zlib 1.3.1
               mbedtls 3.6.2
                  curl 8.6.0
         nlohmann_json 3.11.3
```

Fetching a package resolves its hash with `zig fetch` and writes the entry into
`build.zig.zon`:

```bash
zig build zaza-fetch -- fmt
```

The rest of the CLI:

```text
zaza fetch <name>    Fetch a package from the registry into build.zig.zon (alias: add)
zaza add <name>      Alias for fetch
zaza remove <name>   Remove a dependency from build.zig.zon (alias: rm)
zaza list            List all packages available in the registry (alias: ls)
zaza deps            List dependencies with source, lock state, and on-disk presence
zaza clean-deps      Remove deps/ and zig-out/deps (alias: clean)
zaza cache           Show the Zig cache directories and whether they are writable
zaza search <query>  Search packages by name
zaza init [name]     Scaffold a new Zaza project in the current directory
```

`zaza deps` reads `build.zig.zon` for the declared names and `zaza.lock` for
what has been pinned, and checks `deps/` for what is present on disk:

```bash
zig run scripts/zaza.zig -- deps
```

```text
Dependencies (7):
  name             source     hash           on disk
  mbedtls          unlocked   -              no
  fmt              registry   1220abcdef0123 yes
  ...
```

`fetch` resolves the hash with `zig fetch` and records it in both
`build.zig.zon` and `zaza.lock`, so a fetched dependency shows its source and
hash here. `unlocked` means there is no `zaza.lock` entry pinning it yet.

`zaza clean-deps` removes the fetched sources in `deps/` and their built outputs
in `zig-out/deps`, so the next build re-fetches from the pinned hashes. `zaza
cache` reports the global and local Zig cache directories and whether each is
writable, which is the first thing to check when a build fails with a cache
error:

```bash
zig run scripts/zaza.zig -- cache
```

```text
Zig cache directories:
  global   /Users/you/.cache/zig  (writable)
  local    .zig-cache (default)  (writable)
```

The root build also resolves registry entries on your behalf. If an enabled
example needs a package that is missing from `build.zig.zon`, the build adds it
and stops with a message telling you to re-run. `ZAZA_REGISTRY=0` disables that.

### The CMake interop shim

Some libraries only build with CMake. Zaza models those as dependencies with
`type = .CMake`, and the graph clones, configures, builds, and installs them:

```zig
.deps = &.{
    .{
        .name = "fmt",
        .url = "https://github.com/fmtlib/fmt.git",
        .git_ref = "10.2.1",
        .type = .CMake,
        .cmake_config = .{
            .install_prefix = "zig-out/deps",
            .install = true,
            .configure_args = &.{ "-DFMT_DOC=OFF", "-DFMT_TEST=OFF", "-DFMT_INSTALL=ON" },
        },
    },
},
.deps_build_system = .CMake,
.main_build_system = .Zig,
```

Sources land in `deps/<name>/`, build trees in `deps/<name>/build/<Config>/`,
and installed output in `zig-out/deps/`. The final artifact is built by Zig and
links against the installed archives.

Three examples of increasing difficulty:

```bash
ZAZA_EXAMPLES=cmake-shim ZAZA_SYSTEM_CMDS=1 zig build cmake-shim-run
```

```text
{
    "awesome": true,
    "name": "C++ with Zig"
}
```

```bash
ZAZA_EXAMPLES=cmake-combo zig build cmake-combo-run
```

```text
[2026-07-21 12:06:42.346] [info] hello from cmake_combo
```

```bash
ZAZA_EXAMPLES=cmake-net zig build cmake-net-run
```

```text
cmake_net
curl: libcurl/8.6.0-DEV mbedTLS/3.6.2 zlib/1.3.1
zlib: 1.3.1
mbedtls: 3.6.2
```

The last one is the interesting case: curl is configured against the zlib and
mbedtls that the same graph installed a moment earlier.

Interop runs the other way too. `export_cmake = true` writes a
`<name>Config.cmake` into `zig-out/cmake/`, so a CMake project can consume a
Zaza-built library.

---

## Environment variables

Three variables gate behaviour you will hit immediately.

### `ZAZA_EXAMPLES`

Restricts which examples are wired into the root build graph. The value is a
comma-separated list of example names, matched case-insensitively. Whitespace
around each entry is trimmed and empty entries are ignored.

If the variable is unset, every example is enabled. If it is set, only the
listed names are enabled. Any value that matches nothing, including `none`,
disables all of them; `none` is a convention rather than a keyword.

```bash
ZAZA_EXAMPLES=none zig build test              # no examples at all
ZAZA_EXAMPLES=mixed-stack zig build mixed-stack-run
ZAZA_EXAMPLES=wasm-wasi,wasm-exports zig build wasm-wasi-report
```

This matters more than it looks. Zig resolves every declared dependency while
the build graph is being constructed, before any step runs. With all examples
enabled, configuring the graph pulls in JUCE, curl, mbedtls, zlib, spdlog, and
fmt. `ZAZA_EXAMPLES=none` is what CI uses for the fast job, and it is the right
default for the edit-test loop.

The names are the target prefixes: `json`, `juce`, `zaza-juce`, `rust-interop`,
`proof-library`, `generated-code`, `package-producer`, `package-consumer`,
`mixed-stack`, `interface-object-graph`, `test-workflows`, `generated-headers`,
`shared-plugin`, `preset-profiles`, `cross-compile-cli`, `resources-bundle`,
`bindings`, `benchmark-workflow`, `cxx20-modules`, `wasm-wasi`, `wasm-exports`,
`cmake-combo`, `cmake-net`, `cmake-shim`.

`hello-zaza` and `run-hello-zaza` are registered unconditionally and are present
even under `ZAZA_EXAMPLES=none`.

### `ZAZA_SYSTEM_CMDS`

Enables build steps that shell out to external tools, chiefly `git` and `cmake`.
Accepts `1`, `true`, `yes`, `on` and their negatives; the default is off. The
build-time flag `-Dsystem-cmds=true` does the same thing and takes precedence.

```bash
ZAZA_SYSTEM_CMDS=1 zig build cmake-shim
```

When it is off, the build prints its state at the top of every run:

```text
[config] system-cmds=false (deps must already exist)
```

and `cmake-shim` reports that it is skipping:

```text
[cmake-shim] skipped: system-cmds=false. Run with -Dsystem-cmds=true or ZAZA_SYSTEM_CMDS=1 to enable.
```

With it on:

```text
[config] system-cmds=true (git/cmake enabled)
```

The gate exists so that a routine build never silently clones repositories or
invokes CMake. Three examples opt themselves in regardless, because their whole
point is CMake: `cmake_combo`, `cmake_net`, and the JUCE examples. Only
`cmake_shim` genuinely requires the variable.

Note that `cmake-shim-run` and `cmake-install` are registered only when system
commands are enabled. Without the variable those step names do not exist.

### `ZAZA_REGISTRY`

Controls whether the build is allowed to modify `build.zig.zon`. Default on.

When on, the build checks each enabled example's registry dependencies against
`build.zig.zon`. If one is missing, it runs the fetch path, writes the entry
with a resolved hash, prints a message, and panics so you re-run:

```text
[zaza] added dependency 'fmt' to build.zig.zon; re-run zig build
```

Setting `ZAZA_REGISTRY=0` skips that check entirely. Use it when you want the
build to fail loudly on a missing dependency rather than edit a tracked file, or
when you are working offline. It does not disable dependencies already declared
in `build.zig.zon`.

Only five examples trigger a fetch: `juce` and `zaza-juce` need `juce`,
`cmake-combo` needs `fmt` and `spdlog`, `cmake-net` needs `curl`, `zlib`, and
`mbedtls`, and `json` needs `nlohmann_json`.

### The rest

| Variable | Effect |
| --- | --- |
| `ZAZA_PRESET` | Selects a named `BuildConfig` set. See [Presets](#presets). |
| `ZAZA_TARGET` | Overrides the root target triple, e.g. `x86_64-windows-gnu`. Invalid values panic. |
| `ZAZA_WINDOWS_TOOLCHAIN` | Set to `gnu` on Windows hosts to target `native-windows-gnu`. |
| `ZAZA_MODULES_CXX` | Compiler used by the C++20 modules example. Defaults to `/opt/homebrew/opt/llvm/bin/clang++`. |
| `ZIG_GLOBAL_CACHE_DIR` | Zig's global cache. The build refuses to start if it is not writable. |
| `ZIG_LOCAL_CACHE_DIR` | Zig's per-project cache. |

---

## The example matrix

Twenty-seven directories live under `examples/`. Each has a README covering what
it demonstrates, its prerequisites, and the exact command to build and run it.
[`examples/README.md`](../examples/README.md) is the index.

Eighteen of them form the verified matrix, run in sequence by one target:

```bash
zig build example-matrix
```

That runs, in order:

```text
run-hello-zaza              proof-library-run           generated-code-run
package-consumer-run        mixed-stack-run             interface-object-graph-run
test-workflows-run          generated-headers-run       shared-plugin-run
preset-profiles-run         cross-compile-cli-report    resources-bundle-run
bindings-run                benchmark-workflow-run      cxx20-modules-run
wasm-wasi-report            wasm-exports-run            wasm-web-demo-smoke
```

Each entry shells out to `./zig build <target>`, so the wrapper must exist. Runs
are chained rather than parallel, which keeps failure attribution simple.

The matrix omits the examples that need network access or heavy external
toolchains: the three CMake examples, the two JUCE examples, `json`, and
`rust_interop`. Those are documented individually and run on their own.

### What each one covers

| Example | Command | Demonstrates |
| --- | --- | --- |
| hello_zaza | `zig build run-hello-zaza` | A Zig exe and a C++ exe in one graph |
| proof_library | `zig build proof-library-run` | A static library with install/export metadata |
| generated_code | `zig build generated-code-run` | A custom command generating a `.cpp` |
| generated_headers | `zig build generated-headers-run` | A custom command generating a header |
| package_producer | `zig build package-producer-run` | Publishing headers, an archive, and a manifest |
| package_consumer | `zig build package-consumer-run` | Consuming that package from a separate build |
| mixed_stack | `zig build mixed-stack-run` | C library, C++ bridge, Zig executable |
| interface_object_graph | `zig build interface-object-graph-run` | Object library folded into a static library |
| test_workflows | `zig build test-workflows-run` | Run modes differing by arg, env, and cwd |
| shared_plugin | `zig build shared-plugin-run` | A shared library loaded at runtime via `dlopen` |
| preset_profiles | `zig build preset-profiles-run` | `ZAZA_PRESET` selecting a configuration |
| cross_compile_cli | `zig build cross-compile-cli-report` | A nested build for a non-host triple |
| resources_bundle | `zig build resources-bundle-run` | A runtime asset staged into `zig-out/share` |
| bindings | `zig build bindings-run` | Zig calling C++ across a C ABI wrapper |
| benchmark_workflow | `zig build benchmark-workflow-run` | A benchmark as size-specific run targets |
| cxx20_modules | `zig build cxx20-modules-run` | A C++20 named-module pipeline |
| wasm_wasi | `zig build wasm-wasi-report` | A `wasm32-wasi-musl` executable, validated |
| wasm_exports | `zig build wasm-exports-run` | A freestanding wasm module with exports |
| rust_interop | `zig build rust-interop-run` | A Cargo staticlib linked into a Zig executable |
| json | `zig build run` | nlohmann/json as a Zig package dependency |
| cmake_shim | `zig build cmake-shim-run` | The smallest complete CMake interop path |
| cmake_combo | `zig build cmake-combo-run` | fmt + spdlog built by CMake, linked by Zig |
| cmake_net | `zig build cmake-net-run` | curl + zlib + mbedtls with an ordering constraint |
| juce | `zig build juce` | A JUCE GUI app through JUCE's CMake integration |
| zaza-juce | `zig build zaza-juce` | A JUCE audio app with the audio modules on |

Prefix each with `ZAZA_EXAMPLES=<name>` to build just that example.

Two of the twenty-six directories are not examples. `examples/cmake` is an early experiment that is not
wired into the root build and does not compile as written. `examples/json`
builds the repo-root `src/main.cpp` rather than its own source file.

---

## WebAssembly

Two targets and one browser workflow.

### WASI

A `wasm32-wasi-musl` executable, validated as a real WebAssembly binary:

```bash
ZAZA_EXAMPLES=wasm-wasi zig build wasm-wasi
ZAZA_EXAMPLES=wasm-wasi zig build wasm-wasi-report
```

```text
wasm wasi valid
```

The artifact is `zig-out/bin/wasm_wasi_demo.wasm`, runnable under any WASI
runtime. The report step uses Node's `WebAssembly.validate`.

### Freestanding exports

A module with no entry point that exports functions for a host to call:

```zig
const target = b.resolveTargetQuery(.{
    .cpu_arch = .wasm32,
    .os_tag = .freestanding,
});
// ...
exe.entry = .disabled;
exe.rdynamic = true;
```

```bash
ZAZA_EXAMPLES=wasm-exports zig build wasm-exports-run
```

```text
wasm add: 42
wasm mul_add: 42
```

The run step instantiates the module in Node and calls two exports.

### Browser

The same `.wasm` staged into a servable directory alongside an HTML page and a
JS loader:

```bash
ZAZA_EXAMPLES=wasm-exports zig build wasm-web-demo        # stage
ZAZA_EXAMPLES=wasm-exports zig build wasm-web-demo-smoke  # verify over HTTP
ZAZA_EXAMPLES=wasm-exports zig build wasm-web-demo-serve  # serve
```

Everything lands under `zig-out/www/wasm-exports/`.

`wasm-web-demo-smoke` starts the server on port 8123, requests `/index.html`,
`/app.js`, and `/wasm_exports_demo.wasm`, then exits:

```text
Serving zig-out/www/wasm-exports at http://127.0.0.1:8123
```

`wasm-web-demo-serve` binds `http://127.0.0.1:8000` and runs until interrupted.
The server is `build_lib/static_server.zig`, built as part of the graph, so
there is no external dependency for local serving.

---

## Fast rebuilds

A build through `zig build` compiles and runs the build script on every
invocation. That is most of a no-op rebuild's cost. Measured on an Apple M4 Max
with Zig 0.15.2, the no-op is close to a measurement of `zig build` startup:
about 39 ms to run a trivial build script, about 69 ms before any target
declared, about 84 ms for the 16 translation unit project used in the benchmark.
Ninja parses a static manifest and answers in about 4 ms.

`zaza-drive` closes that gap. It is a native build driver that reads a manifest,
stats the sources and the header dependencies each object recorded via
`-MMD -MF`, compiles only what changed, and links only when an object changed. A
no-op is a handful of `stat` calls and an exit. Same 16 unit workload, same
machine, same compiler in every lane:

| phase | zaza-drive | ninja | zig build |
| --- | --- | --- | --- |
| no-op rebuild | 2.3 ms | 3.3 ms | 69.7 ms |
| incremental rebuild | 110.4 ms | 121.4 ms | 106.1 ms |

On the no-op zaza-drive beats Ninja by a wide margin. On the incremental it is
level with `zig build`, because once a real translation unit recompiles the
compiler does the same work in every lane and that work dominates.

### The native compiler fast path

The remaining cost is process startup, paid twice on an incremental rebuild:
once to compile, once to link. The `zig c++` wrapper is about twice the
per-invocation cost of the system compiler. Measured, one trivial translation
unit, median of ten: `zig c++ -c` at ~31 ms against Apple `clang++ -c` at ~15 ms.

`zig build drive-native` writes a manifest that uses the system default
compiler. On the same 16 unit workload the incremental rebuild drops from 127 ms
to 47 ms, about 2.7x.

The system compiler is a different compiler from Zig's bundled one. It does not
cross-compile and can differ in behaviour, so this is an iteration path. Release
and cross builds go through `zig build`, or through `zig build drive`, which
writes a manifest that uses the faithful `zig c++`. The two caches never mix:
native objects live in `.zaza-drive-native/`, faithful ones in `.zaza-drive/`.

```bash
zig build drive-native
./zig-out/bin/zaza-drive zig-out/build-native.manifest
```

`tools/zaza-drive/README.md` documents the driver, its correctness check, and
watch mode. The benchmark that produced these numbers is in `benchmarks/`; run
`./tools/zaza-drive/bench.sh` to reproduce them on your own machine.

---

## Testing and benchmarks

A test or a benchmark in Zaza is an executable plus a list of run cases. Each
case is data: a label, arguments, an environment, and a working directory. The
API in `build_lib/test_suite.zig` turns that list into the run steps and the
per-case and aggregate build steps, so a build file states what to run instead
of wiring run steps by hand.

```zig
const cpp = @import("../../build_lib/cpp_example.zig");
const test_suite = @import("../../build_lib/test_suite.zig");

const demo = cpp.CppExample.executable(.{
    .name = "workflows_demo",
    .description = "workflow example",
    .source_files = &.{"examples/test_workflows/src/main.cpp"},
    .cpp_std = "17",
});

_ = try test_suite.addTest(b, target, .{
    .name = "test-workflows",
    .target = demo,
    .cases = &.{
        .{ .label = "unit", .args = &.{"unit"},
           .env = &.{.{ .name = "WORKFLOW_MODE", .value = "unit" }},
           .cwd = b.path("examples/test_workflows") },
        .{ .label = "integration", .args = &.{"integration"} },
        .{ .label = "smoke", .args = &.{"smoke"} },
    },
});
```

That call produces `test-workflows` (build), `test-workflows-run` (every case),
and one `test-workflows-<label>` step per case. Because `hook_test_step`
defaults to true, `zig build test` runs the cases too.

A `RunCase` has four fields. `label` names the run step and its per-case step.
`args` are passed to the process. `env` is a list of `{ name, value }` pairs.
`cwd` is an optional `LazyPath` for the working directory. Only `label` is
required.

The compiler and optimize mode come from the `CppExample.configs` the target
carries, the same way the rest of Zaza chooses them. A test compiles with the
same flags as the normal build because it is built through the same
`buildWithTarget`.

### Benchmarks

`addBench` has the same shape and different defaults. It builds in release (the
target sets `.configs = cpp.BuildConfigs.release_only`), stays off the `test`
step, inherits stdio so timings reach the terminal, and forwards
`zig build <step> -- --reps 9` to every case.

```zig
const bench = cpp.CppExample.executable(.{
    .name = "bench_suite_demo",
    .description = "benchmark example",
    .source_files = &.{"examples/bench_suite/src/main.cpp"},
    .cpp_std = "17",
    .configs = cpp.BuildConfigs.release_only,
});

_ = try test_suite.addBench(b, target, .{
    .name = "bench-suite",
    .target = bench,
    .cases = &.{.{ .label = "compute" }},
});
```

```sh
zig build bench-suite-run              # default reps
zig build bench-suite-run -- --reps 9  # forwarded to the process
```

A test asserts and belongs on `test`. A benchmark measures and does not, so it
stays off `test` and prints its numbers. The two examples this API drives are
`examples/test_workflows` and `examples/bench_suite`, both in
`zig build example-matrix`.

---

## Troubleshooting

### The build panics about the Zig cache

```text
Zig cache is not writable. Set ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR,
or enable direnv (see .envrc) for a portable setup.
```

The build checks for a writable cache directory before doing anything else. Set
both variables explicitly, or use the committed `.envrc`:

```bash
export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-cache-global"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
```

The `./zig` wrapper sets both for you.

### A nested build fails with exit code 127

```text
error: the following command exited with error code 127:
env ZAZA_EXAMPLES=package-producer ./zig build install
```

`./zig` is missing. It is gitignored, so a fresh clone does not have one. Run
`./setup.sh`, which creates it.

Affected targets: `package-consumer`, `cross-compile-cli`, `rust-interop`, and
`example-matrix`.

### CMake complains that the cache directory does not match

```text
CMake Error: The current CMakeCache.txt directory .../deps/json/build/Debug/CMakeCache.txt
is different than the directory .../deps/json/build/Debug where CMakeCache.txt was created.
```

CMake caches absolute paths. If the checkout moved, or the build tree was copied
from another machine, every cached path is wrong. Delete the build tree for the
dependency and rebuild:

```bash
rm -rf deps/<name>/build
```

The JUCE examples keep their build tree inside the example directory:

```bash
rm -rf examples/juce/build
rm -rf examples/zaza-juce/build
```

Source checkouts under `deps/` are unaffected, so this does not force a re-clone.

### A build seems to hang while configuring

It is probably resolving dependencies. Zig resolves everything declared in the
graph before running any step, so enabling all examples means fetching JUCE,
curl, mbedtls, zlib, spdlog, and fmt. Scope the build:

```bash
ZAZA_EXAMPLES=<name> zig build <target>
```

### `run-cpp` fails on a file that compiles fine elsewhere

`run-cpp` invokes `zig c++` by name, so Zig must be on PATH, and it passes no
include directories of its own. A file that includes a project header will fail:

```text
examples/hello_zaza/src/main.cpp:2:10: fatal error: 'hello_zaza.h' file not found
```

Pass the flags yourself, after the source path:

```bash
zig build run-cpp -- src/simple_example.cpp -O2
```

### `ZAZA_PRESET=asan` or `ZAZA_PRESET=lto` fails to link

Both are toolchain-dependent rather than broken. `asan` needs the AddressSanitizer
runtime to be available to the linker. `lto` needs the toolchain to be using LLD.
Neither is guaranteed on a given machine.

### The C++20 modules example cannot find a compiler

The example does not use `zig c++`, because `zig c++` rejects `-x c++-module` and
ignores `-fmodule-output`. It uses `/opt/homebrew/opt/llvm/bin/clang++` by
default. Point it elsewhere:

```bash
ZAZA_MODULES_CXX=/path/to/clang++ zig build cxx20-modules-run
```

### Benchmarks

`benchmarks/` holds one benchmark. It generates a synthetic C++ project, builds
it with `zig build` and with CMake plus Ninja, and times the real processes:

```bash
zig build --build-file benchmarks/build.zig bench
```

It runs on 0.14.1 and 0.15.2. On 0.16.0 the step fails with a message, because
the harness uses `std.process.Child.run`, which 0.16 removed. Nothing in
`zig build test` or `zig build example-matrix` reaches this build file.

Four earlier files here (`performance_benchmark.zig`, `memory_benchmark.zig`,
`scalability_benchmark.zig`, `cmake_comparison.zig`) computed their results from
hardcoded constants instead of measuring anything, and did not compile. They
were deleted. See `benchmarks/README.md` for the details, and do not restore
them from history.

### A tracked file changed after a build

Two files at the repo root are generated output and gitignored: `CMakeLists.txt`
and `build/CMakeLists.txt`. They are rewritten by whichever CMake-exporting
example built last. Leave them out of commits.

Note that the top-level `build/` directory itself holds real tracked Zig sources
that `build.zig` imports. Only the generated CMake output inside it is ignored.

### Which Zig versions actually work

0.14.1, 0.15.2 and 0.16.0. All three are verified against the full test suite:

```text
Build Summary: 43/43 steps succeeded; 87/87 tests passed
```

The sources use spellings valid in all three. Where no shared spelling exists,
a `if (comptime @hasDecl(...))` picks one: the `std.Io` filesystem move,
`ArrayList.writer`, `Compile`'s `add*`/`link*` forwarders, and `std.json`'s
unmanaged `ObjectMap`. Other versions may work and are not tested. `setup.sh`
warns when it sees one.

To test a specific lane, pass the compiler explicitly:

```sh
ZIG=/path/to/zig-0.14.1 ./setup.sh
ZIG=/path/to/zig-0.15.2 ./setup.sh
ZIG=/path/to/zig-0.16.0 ./setup.sh
```

The generated `./zig` wrapper points at the selected binary and keeps local
cache paths stable for nested build steps. Setup also uses a
Zig-version-specific `--cache-dir` by default, which avoids stale build runners
when switching between the 0.14, 0.15, and 0.16 lanes.

---

## Where to go next

| Document | Covers |
| --- | --- |
| [`examples/README.md`](../examples/README.md) | Every example, its command, and its purpose |
| [`EXAMPLES.md`](EXAMPLES.md) | Per-example diagrams and the syntax each one focuses on |
| [`SYNTAX_REFERENCE.md`](SYNTAX_REFERENCE.md) | The full `CppExample` field list and command surface |
| [`CMAKE_PARITY.md`](CMAKE_PARITY.md) | Feature-by-feature parity status and priorities |
| [`ROADMAP.md`](ROADMAP.md) | What is being built next |
| [`IMPLEMENTATION.md`](IMPLEMENTATION.md) | How the internals fit together |
| [`JUCE_WINDOWS.md`](JUCE_WINDOWS.md) | JUCE notes for Windows |

Source, issues, and discussion:
[github.com/godofecht/zaza](https://github.com/godofecht/zaza)
