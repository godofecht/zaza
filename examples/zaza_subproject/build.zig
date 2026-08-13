//! The zaza-to-zaza `add_subdirectory` path.
//!
//! `libs/greet` is a Zaza subproject: it keeps its own `build.zig` and builds
//! its own `greet` library. This parent build imports that `build.zig`, calls
//! its `subproject` function, and links the exposed library into a Zaza-built
//! executable. One build graph, so the library and its headers propagate
//! natively. This is how a Zaza project splits into reusable subprojects.

const std = @import("std");
const zaza = @import("../../build_lib/zaza.zig");
const greet_build = @import("libs/greet/build.zig");

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const greet = greet_build.subproject(b, target);

    const exe = zaza.Target.executable(.{
        .name = "zaza_subproject_demo",
        .description = "zaza top-level linking a zaza subproject library",
        .source_files = &.{"examples/zaza_subproject/src/main.cpp"},
        .cpp_std = "17",
        .configs = zaza.config_sets.release_only,
    }).buildWithTarget(b, target) catch @panic("zaza_subproject example: build failed");

    greet.linkInto("greet", exe);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("zaza-subproject-run", "Run the zaza_subproject example");
    run_step.dependOn(&run.step);

    const build_step = b.step("zaza-subproject", "Build the zaza_subproject example");
    build_step.dependOn(&exe.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    addSteps(b, target);
}
