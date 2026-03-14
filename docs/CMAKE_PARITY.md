# Zaza CMake Parity Plan

This is the practical feature plan for making Zaza good enough to replace CMake
for new projects, not a vague wishlist.

## Goal

Zaza does not need to clone every historical CMake feature. It needs to cover the
subset that modern C/C++ projects actually depend on:

- native executable/library targets
- transitive usage requirements
- install/export/package consumption
- dependency fetching and reproducible locks
- test/benchmark/custom command workflows
- cross compilation and toolchain control
- IDE/tooling outputs

If Zaza does those reliably, new projects can start on Zaza without feeling like
they are giving something important up.

## Current Position

Already present in the repo:

- Zig-native build scripting
- C++ target construction via `CppExample`
- mixed Zig + C++ targets
- basic install/export support
- partial `compile_commands.json` support
- partial CMake-dependency shimming
- registry-driven dependency autofetch
- minimal generator-expression handling

Still missing or incomplete for true replacement:

- first-class target model for libraries, not just example-driven executables
- robust transitive propagation of include dirs, defines, link flags, link order
- proper custom command / generated source support
- test discovery and richer test orchestration
- package consumption parity with `find_package` style workflows
- presets, profiles, and reproducible configuration sets
- toolchain and platform abstraction at the target level
- object libraries, interface libraries, alias targets
- precompiled headers, unity builds, sanitizer/LTO profiles
- polished IDE/editor integration

## Priority Tiers

### Tier 0: Must Work

Without this, Zaza is not a credible replacement for new projects.

1. First-class target API
- `addExecutable`
- `addStaticLibrary`
- `addSharedLibrary`
- `addObjectLibrary`
- `addInterfaceLibrary`
- target dependencies by target reference, not raw path strings

2. Usage requirements
- public/private/interface include directories
- public/private/interface compile definitions
- public/private/interface compile options
- public/private/interface link options
- transitive propagation across dependency edges

3. Install/export/package consumption
- install binaries, headers, libs, resources
- generate importable package metadata
- consume installed Zaza packages cleanly from another project
- stable package layout in `zig-out`

4. Deterministic dependencies
- lockfile with exact source revision/hash
- local override mechanism for development
- offline mode that does not silently refetch
- explicit update flow

5. Custom commands and generated files
- run code generators before compile
- model input/output files for incremental rebuilds
- support generated headers and generated sources

6. Tests
- declare tests as first-class targets
- run tests selectively
- support working directories, env vars, args, labels
- failure summaries that are readable

7. Toolchain/platform controls
- target triples
- compiler/linker overrides
- sysroot / SDK configuration
- platform-specific target properties without ad hoc branching everywhere

8. Tooling outputs
- correct `compile_commands.json`
- exported include/define/link manifest
- IDE-stable output paths

### Tier 1: Strongly Needed

These are common in serious projects and should follow immediately after Tier 0.

1. Presets and profiles
- debug/release/asan/tsan/ubsan/lto
- named presets committed to the repo
- local override file ignored by git

2. Package discovery model
- a Zaza equivalent to `find_package`
- explicit imported targets from installed packages
- version constraints

3. Multi-config and configuration expressions
- richer config-specific values
- platform-specific expressions
- target-property interpolation

4. Resource/install helpers
- copy assets into runtime layout
- install data files
- bundle app resources on macOS/Windows

5. Better CMake interop
- dependable shim for CMake-only dependencies
- import target metadata from CMake installs
- clearer errors when shimmed deps are misconfigured

6. Project composition
- `add_subdirectory` equivalent
- reusable subprojects
- workspace-level target namespaces

### Tier 2: Important for Adoption

These improve performance and polish enough to matter commercially.

1. Build performance features
- precompiled headers
- unity builds
- ccache/sccache integration
- better graph parallelism diagnostics

2. Developer ergonomics
- `zaza fmt`, `zaza doctor`, `zaza graph`, `zaza deps`
- explain-why rebuild diagnostics
- cache inspection and cleanup commands

3. Editor support
- VS Code extension
- target/task discovery
- hover/help for Zaza target APIs

4. CI/release workflows
- test report export
- artifact packaging
- release bundle generation

### Tier 3: Nice to Have

Useful, but not required for replacing CMake on most new projects.

- visual build graph UI
- remote/distributed build orchestration
- package registry hosting
- migration assistant from large legacy CMake trees

## Concrete Feature Mapping

| CMake concept | Zaza requirement | Status |
| --- | --- | --- |
| `add_executable` | stable executable target API | partial |
| `add_library(STATIC/SHARED)` | native library target API | missing |
| `target_link_libraries` | target-to-target linking with visibility scopes | partial |
| `target_include_directories` | usage requirements with transitive propagation | partial |
| `target_compile_definitions` | scoped compile definitions | partial |
| `target_compile_options` | scoped compile flags | partial |
| `target_link_options` | scoped linker flags | partial |
| `add_custom_command` | generated file pipeline with inputs/outputs | missing |
| `add_custom_target` | phony orchestration targets | partial |
| `enable_testing` / `add_test` | first-class test model | partial |
| `install` | install layout and rules | partial |
| `export` / package config | reusable downstream package metadata | partial |
| `find_package` | package discovery/imported targets | missing |
| `FetchContent` | reproducible dependency fetch + lock | partial |
| presets/toolchains | named config + toolchain model | partial |
| generator expressions | config/platform-conditioned values | partial |
| `add_subdirectory` | composition of subprojects | missing |
| object/interface/alias libs | target graph richness | missing |
| `compile_commands.json` | tooling integration | partial |

## Recommended Execution Order

### Phase 1: Fix the core target model

Build this first:

- generalize `CppExample` into reusable target primitives
- add native static/shared/interface/object library support
- implement scoped usage requirements with transitive propagation
- add target graph tests that assert include/define/link behavior

Exit criteria:

- one repo can declare a shared lib, a static lib, an interface lib, and an exe
- dependent targets inherit exactly the intended public/interface settings

### Phase 2: Make dependency and package consumption real

Build this next:

- formal lockfile
- package install/export metadata
- downstream package import API
- local path overrides for active development

Exit criteria:

- project A installs a package
- project B consumes it without manual include/lib path wiring

### Phase 3: Generated sources, tests, and presets

Build this next:

- custom commands with tracked outputs
- test target API
- preset/profile system
- env/arg/working-dir support

Exit criteria:

- protobuf/codegen-style project builds correctly
- CI can select presets and test labels cleanly

### Phase 4: CMake interop and migration quality

Build this next:

- reliable CMake shim path for third-party deps
- import installed CMake package metadata where possible
- improve diagnostics around external dependency failures

Exit criteria:

- common CMake-only libraries can be consumed without hand debugging

## What To Avoid

Do not spend the next phase on these before Tier 0 is solid:

- package registry hosting
- GUI build editors
- distributed builds
- ambitious IDE products
- broad marketing claims about replacing CMake

Those are multipliers. They are not the foundation.

## Immediate Repo Work Items

These are the highest-value changes implied by the current codebase:

1. Split `CppExample` into a real target layer plus thin example wrappers.
2. Add `StaticLibrary`, `SharedLibrary`, and `InterfaceLibrary` support.
3. Add target-graph tests for transitive include/define/link propagation.
4. Design a lockfile format and wire it into current registry fetching.
5. Add `addCustomCommand`-style generated-file support.
6. Introduce a package import/export story stronger than handwritten paths.
7. Add presets for `debug`, `release`, `asan`, and `lto`.

## Success Standard

Zaza is ready to replace CMake for new projects when a team can start a
cross-platform C++ library/executable project with tests, third-party
dependencies, install/export packaging, generated code, and editor tooling
without needing to fall back to CMake for any core workflow.
