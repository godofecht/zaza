//! A unity build: several sources compiled as one translation unit.
//!
//! `unity_build = true` makes Zaza generate one translation unit that includes
//! part_a.cpp, part_b.cpp, and main.cpp, then compile that single unit. The
//! `CMAKE_UNITY_BUILD` equivalent, it parses the shared headers once instead of
//! once per source, which speeds a cold build.

const std = @import("std");
const zaza = @import("../../build_lib/zaza.zig");

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const exe = zaza.Target.executable(.{
        .name = "unity_demo",
        .description = "three sources compiled as one translation unit",
        .source_files = &.{
            "examples/unity_build/src/part_a.cpp",
            "examples/unity_build/src/part_b.cpp",
            "examples/unity_build/src/main.cpp",
        },
        .public_include_dirs = &.{"examples/unity_build/include"},
        .unity_build = true,
        .cpp_std = "17",
        .configs = zaza.config_sets.release_only,
    }).buildWithTarget(b, target) catch @panic("unity_build example: build failed");

    const run = b.addRunArtifact(exe);
    const run_step = b.step("unity-build-run", "Run the unity_build example");
    run_step.dependOn(&run.step);

    const build_step = b.step("unity-build", "Build the unity_build example");
    build_step.dependOn(&exe.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    addSteps(b, target);
}
