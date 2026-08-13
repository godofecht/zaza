//! The `add_subdirectory` migration path.
//!
//! `vendor/mathlib` is an existing CMake component, kept as-is. Zaza drives
//! CMake to build it, then links the resulting library into a Zaza-built
//! executable. The subtree stays CMake; the top-level build is Zaza. This is
//! how a project migrates off CMake one piece at a time.

const std = @import("std");
const zaza = @import("../../build_lib/zaza.zig");

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const sub = zaza.addCMakeSubdirectory(b, .{
        .path = "examples/cmake_subdir/vendor/mathlib",
        .lib = "mathlib",
        .include_dirs = &.{"examples/cmake_subdir/vendor/mathlib/include"},
    });

    const exe = zaza.Target.executable(.{
        .name = "cmake_subdir_demo",
        .description = "zaza top-level linking a CMake-built in-tree subdirectory",
        .source_files = &.{"examples/cmake_subdir/src/main.c"},
        .c_std = "11",
        .configs = zaza.config_sets.release_only,
    }).buildWithTarget(b, target) catch @panic("cmake_subdir example: build failed");

    sub.linkInto(exe);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("cmake-subdir-run", "Run the cmake_subdir example");
    run_step.dependOn(&run.step);

    const build_step = b.step("cmake-subdir", "Build the cmake_subdir example");
    build_step.dependOn(&exe.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    addSteps(b, target);
}
