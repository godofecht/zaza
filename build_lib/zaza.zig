//! Zaza public API.
//!
//! This is the stable entry module for build files. Import it once and reach
//! the supported surface through it:
//!
//! ```zig
//! const std = @import("std");
//! const zaza = @import("build_lib/zaza.zig");
//!
//! pub fn build(b: *std.Build) !void {
//!     const exe = try zaza.Target.executable(.{
//!         .name = "my_app",
//!         .source_files = &.{"src/main.cpp"},
//!         .public_include_dirs = &.{"include"},
//!         .public_defines = &.{"MY_APP=1"},
//!         .cpp_std = "17",
//!     }).build(b);
//!
//!     const run = b.addRunArtifact(exe);
//!     const run_step = b.step("run", "Run my_app");
//!     run_step.dependOn(&run.step);
//! }
//! ```
//!
//! Everything re-exported here is part of the supported surface. The sibling
//! modules under `build_lib/` stay importable so existing build files keep
//! working. This facade re-exports from them without copying logic, so the two
//! never drift. See `docs/API.md` for the full reference.

const std = @import("std");

const cpp = @import("cpp_example.zig");
const test_suite = @import("test_suite.zig");
const presets = @import("presets.zig");
const cmd = @import("zaza_cmd.zig");
const rust = @import("rust_example.zig");

/// The Zig lanes Zaza is validated on. A downstream project reads this to pin a
/// lane and to check compatibility before building. See `docs/LANES.md`.
pub const supported_lanes = [_]std.SemanticVersion{
    .{ .major = 0, .minor = 14, .patch = 1 },
    .{ .major = 0, .minor = 15, .patch = 2 },
    .{ .major = 0, .minor = 16, .patch = 0 },
};

/// True when `v` matches a supported lane by major.minor (patch is advisory).
pub fn laneSupported(v: std.SemanticVersion) bool {
    for (supported_lanes) |lane| {
        if (lane.major == v.major and lane.minor == v.minor) return true;
    }
    return false;
}
const interop = @import("interop_hints.zig");

// --- Targets ------------------------------------------------------------------

/// A C or C++ build target: an executable or a library. It is a plain struct,
/// so a target is data you can inspect and modify before building it. Build it
/// with `Target.build(b)` or `Target.buildWithTarget(b, target)`.
pub const Target = cpp.CppExample;

/// Historic name for `Target`. Kept so existing build files keep working;
/// prefer `Target` in new code.
pub const CppExample = cpp.CppExample;

/// The option bag accepted by the `Target` constructors
/// (`executable`, `staticLibrary`, `sharedLibrary`, `objectLibrary`,
/// `interfaceLibrary`). Most fields default, so a target names only what it
/// needs.
pub const TargetOptions = cpp.TargetOptions;

/// Which artifact a target produces: executable or one of the library kinds.
pub const TargetKind = cpp.TargetKind;

/// A JUCE GUI application builder. It generates a CMake project and drives it,
/// so it needs system commands enabled.
pub const JUCEApplication = cpp.JUCEApplication;

// --- Configurations -----------------------------------------------------------

/// One build configuration: a mode plus its flags, defines, and link inputs.
/// A target carries a list of these in `Target.configs`.
pub const BuildConfig = cpp.BuildConfig;

/// Optimisation intent for a configuration (`Debug`, `Release`,
/// `RelWithDebInfo`, `MinSizeRel`), mapped to Zig optimize modes when built.
pub const BuildMode = cpp.BuildMode;

/// Whether a target or dependency builds through Zig or through CMake.
pub const BuildSystem = cpp.BuildSystem;

/// Single named configurations: `configs.Debug`, `configs.Release`,
/// `configs.RelWithDebInfo`, `configs.MinSizeRel`.
pub const configs = cpp.Configs;

/// Ready-made configuration lists: `config_sets.debug_release`,
/// `config_sets.debug_only`, `config_sets.release_only`.
pub const config_sets = cpp.BuildConfigs;

/// Resolve a preset name to a configuration list. Known names are `debug`,
/// `release`, `relwithdebinfo`, `minsizerel`, `asan`, and `lto`. An unknown
/// name falls back to debug. This is what `ZAZA_PRESET` selects.
pub const presetConfigs = presets.presetConfigs;

/// Resolve a preset name to a configuration list, supporting local override JSON files.
pub const resolvePreset = presets.resolvePreset;

/// Resolve a preset name to a configuration list with a custom allocator, supporting local override JSON files.
pub const resolvePresetWithAllocator = presets.resolvePresetWithAllocator;

// --- Dependencies -------------------------------------------------------------

/// A source dependency: a name, a URL, and how to fetch and build it.
pub const Dependency = cpp.Dependency;

/// CMake settings for a dependency or a CMake-built target.
pub const CMakeConfig = cpp.CMakeConfig;

/// Registry of ready-made dependency descriptions.
pub const Deps = cpp.Deps;

/// Common preprocessor define strings and a `custom` helper.
pub const Defines = cpp.Defines;

/// A named command that produces generated sources, run before compilation.
pub const CustomCommand = cpp.CustomCommand;

/// Extra install-style copies of a built artifact.
pub const ArtifactCopy = cpp.ArtifactCopy;

/// Add extra install-style copies for a manually built artifact.
pub const addArtifactCopies = cpp.addArtifactCopies;

/// Install-style copies of source files or generated files.
pub const FileCopy = cpp.FileCopy;

/// Add install-style file/resource copies to a build graph.
pub const addFileCopies = cpp.addFileCopies;

// --- Target usage graph -------------------------------------------------------
//
// A lighter target model that resolves transitive include dirs, defines, and
// link libraries across dependency edges by visibility. Used to reason about
// usage requirements the way CMake's PUBLIC/PRIVATE/INTERFACE do.

/// A node in the usage graph: a name, a kind, its own usage requirements, and
/// its dependency edges.
pub const CppTarget = cpp.CppTarget;

/// A dependency edge with a visibility.
pub const TargetDependency = cpp.TargetDependency;

/// Include dirs, defines, options, and link inputs that a target needs and may
/// propagate to its consumers.
pub const UsageRequirements = cpp.UsageRequirements;

/// The result of resolving a `CppTarget`: its local and exported requirements
/// and the libraries it links.
pub const ResolvedUsage = cpp.ResolvedUsage;

/// How a usage requirement propagates across a dependency edge.
pub const Visibility = cpp.Visibility;

// --- Tests and benchmarks -----------------------------------------------------

/// Declare a test target: an executable plus labelled run cases. Hooks the
/// cases onto the top `test` step by default.
pub const addTest = test_suite.addTest;

/// Declare a benchmark target. Same shape as a test, with release defaults; it
/// stays off `test`, prints timings, and forwards `-- ...` arguments.
pub const addBench = test_suite.addBench;

/// Options for `addTest`.
pub const TestOptions = test_suite.TestOptions;

/// Options for `addBench`.
pub const BenchOptions = test_suite.BenchOptions;

/// One thing to run against the built executable: a label, arguments, an
/// environment, and a working directory.
pub const RunCase = test_suite.RunCase;

/// A name and value for a run case's environment.
pub const EnvVar = test_suite.EnvVar;

/// What `addTest` and `addBench` return: the built executable and the build,
/// run, and per-case steps.
pub const SuiteResult = test_suite.Result;

// --- Rust interop -------------------------------------------------------------

/// A Rust crate built with Cargo and linked into the Zig build graph.
pub const RustExample = rust.RustExample;

// --- Command helpers ----------------------------------------------------------

/// Add a named system-command step with inherited stdio.
pub const addCommandStep = cmd.addCommandStep;

/// Read an environment variable through the build graph. Portable across the
/// supported Zig versions; the caller frees the returned slice.
pub const envString = cmd.envString;

/// A short remediation hint for a failed system command (cmake, git, python),
/// or null when there is nothing specific to say.
pub const commandHint = interop.commandHint;
