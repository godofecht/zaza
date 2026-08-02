# Zaza public API

This is the supported surface for build files. Import the facade once and reach
everything through it:

```zig
const std = @import("std");
const zaza = @import("build_lib/zaza.zig");

pub fn build(b: *std.Build) !void {
    const exe = try zaza.Target.executable(.{
        .name = "my_app",
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{"include"},
        .public_defines = &.{"MY_APP=1"},
        .cpp_std = "17",
    }).build(b);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run my_app");
    run_step.dependOn(&run.step);
}
```

The facade is `build_lib/zaza.zig`. It re-exports from the modules under
`build_lib/` without copying logic, so the two never drift. The individual
modules stay importable, so build files written against
`build_lib/cpp_example.zig` and the others keep working unchanged.

## Stability

Names in this document are supported. The rest of `build_lib/` is internal: it
may move or change without notice, even when a declaration is `pub`. New build
files should import the facade.

`Target` is the supported name for the C and C++ target type. The old name
`CppExample` is kept as an alias, so existing build files do not need to change.

## Targets

| Name | Kind | Purpose |
| --- | --- | --- |
| `Target` | type | A C or C++ target. Build it with `Target.build(b)` or `Target.buildWithTarget(b, target)`. |
| `CppExample` | type | Alias of `Target`, kept for existing build files. |
| `TargetOptions` | type | The option bag the constructors accept. |
| `TargetKind` | enum | `executable`, `static_library`, `shared_library`, `object_library`, `interface_library`. |
| `JUCEApplication` | type | A CMake-backed JUCE GUI application builder. |

Five constructors cover the kinds. Each takes a `TargetOptions`:

```zig
zaza.Target.executable(...)
zaza.Target.staticLibrary(...)
zaza.Target.sharedLibrary(...)
zaza.Target.objectLibrary(...)
zaza.Target.interfaceLibrary(...)
```

A target is a plain struct, so you can inspect and modify it before building.
The full field list is in [`SYNTAX_REFERENCE.md`](SYNTAX_REFERENCE.md).

## Configurations

| Name | Kind | Purpose |
| --- | --- | --- |
| `BuildConfig` | type | One configuration: a mode plus its flags, defines, and link inputs. |
| `BuildMode` | enum | `Debug`, `Release`, `RelWithDebInfo`, `MinSizeRel`. |
| `BuildSystem` | enum | `Zig` or `CMake`. |
| `configs` | namespace | Single named configurations: `configs.Debug`, `configs.Release`, `configs.RelWithDebInfo`, `configs.MinSizeRel`. |
| `config_sets` | namespace | Ready-made lists: `config_sets.debug_release`, `config_sets.debug_only`, `config_sets.release_only`. |
| `presetConfigs` | fn | Resolve a preset name to a configuration list. |

`presetConfigs(name)` accepts `debug`, `release`, `relwithdebinfo`,
`minsizerel`, `asan`, and `lto`, matched case-insensitively. An unknown name
falls back to debug. This is the same resolution `ZAZA_PRESET` uses.

## Dependencies

| Name | Kind | Purpose |
| --- | --- | --- |
| `Dependency` | type | A source dependency: name, URL, and how to fetch and build it. |
| `CMakeConfig` | type | CMake settings for a dependency or a CMake-built target. |
| `Deps` | namespace | Ready-made dependency descriptions. |
| `Defines` | namespace | Common preprocessor define strings, plus a `custom` helper. |
| `CustomCommand` | type | A named command that produces generated sources. |
| `ArtifactCopy` | type | Extra install-style copies of a built artifact. |
| `addArtifactCopies` | fn | Attach artifact copy steps to a manually built artifact. |

`Target.artifact_copies` is the target-level form for artifacts built through
Zaza. Use it when a plugin, app bundle, or package layout needs the same output
outside the default `zig-out/bin` or `zig-out/lib` location:

```zig
const plugin = zaza.Target.sharedLibrary(.{
    .name = "my_plugin",
    .source_files = &.{"src/plugin.cpp"},
    .artifact_copies = &.{
        .{ .dest_dir = "share/my_host/plugins" },
    },
});
```

For hand-built artifacts, use `addArtifactCopies` with the artifact and an
optional dependency step. The helper returns the last copy step so callers can
depend on it before running a host.

## Target usage graph

A lighter target model that resolves transitive include dirs, defines, and link
libraries across dependency edges by visibility, the way CMake's PUBLIC,
PRIVATE, and INTERFACE do.

| Name | Kind | Purpose |
| --- | --- | --- |
| `CppTarget` | type | A node: a name, a kind, its usage requirements, and its edges. |
| `TargetDependency` | type | A dependency edge with a visibility. |
| `UsageRequirements` | type | Include dirs, defines, options, and link inputs a target needs and may propagate. |
| `ResolvedUsage` | type | The result of resolving a `CppTarget`. |
| `Visibility` | enum | `public`, `private`, `interface`. |

## Tests and benchmarks

A test or a benchmark is an executable plus a list of run cases, where each case
is data: a label, arguments, an environment, and a working directory.

```zig
const demo = zaza.Target.executable(.{
    .name = "demo",
    .source_files = &.{"src/demo.cpp"},
    .include_dirs = &.{},
    .cpp_flags = &.{},
    .deps = &.{},
});

_ = try zaza.addTest(b, target, .{
    .name = "test-workflows",
    .target = demo,
    .cases = &.{
        .{ .label = "unit", .args = &.{"unit"} },
        .{ .label = "integration", .args = &.{"integration"} },
    },
});
```

| Name | Kind | Purpose |
| --- | --- | --- |
| `addTest` | fn | Declare a test target. Hooks its cases onto the top `test` step by default. |
| `addBench` | fn | Declare a benchmark. Release defaults, kept off `test`, prints timings, forwards `-- ...`. |
| `TestOptions` | type | Options for `addTest`. |
| `BenchOptions` | type | Options for `addBench`. |
| `RunCase` | type | One case: a label, arguments, an environment, and a working directory. |
| `EnvVar` | type | A name and value for a case's environment. |
| `SuiteResult` | type | What `addTest` and `addBench` return: the exe and the generated steps. |

`addTest` gives `<name>`, `<name>-run`, and a step per case. `addBench` has the
same shape with release defaults. Full detail is in
[`WIKI.md`](WIKI.md#testing-and-benchmarks); the examples are
[`examples/test_workflows`](../examples/test_workflows) and
[`examples/bench_suite`](../examples/bench_suite).

## Rust interop

| Name | Kind | Purpose |
| --- | --- | --- |
| `RustExample` | type | A Rust crate built with Cargo and linked into the Zig build graph. |

## Command helpers

| Name | Kind | Purpose |
| --- | --- | --- |
| `addCommandStep` | fn | Add a named system-command step with inherited stdio. |
| `envString` | fn | Read an environment variable through the build graph. The caller frees the result. |
| `commandHint` | fn | A short remediation hint for a failed system command, or null. |

## Package CLI

`scripts/zaza.zig` is a separate program, the `zaza` package CLI. It manages
dependencies in `build.zig.zon` and the lockfile and scaffolds a project. It is
a command-line tool, not a build-file import. Run `zaza help` for its commands.
