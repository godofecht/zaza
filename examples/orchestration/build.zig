//! Three build-orchestration features in one target.
//!
//! - A generator-expressioned define: `BUILD_MODE=$<IF:$<CONFIG:Debug>,debug,release>`
//!   resolves against the active config, so the program prints "debug" here.
//! - A target-level linker option (`target_link_options`): `gc_sections` drops
//!   unreferenced sections from the final link.
//! - A phony orchestration target (`add_custom_target`): `orchestration-run`
//!   builds the exe and runs it, all under one named step.

const std = @import("std");
const zaza = @import("../../build_lib/zaza.zig");

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const exe = zaza.Target.executable(.{
        .name = "orchestration_demo",
        .description = "generator-expressioned defines, a link option, and a phony target",
        .source_files = &.{"examples/orchestration/src/main.cpp"},
        .cpp_std = "17",
        // Evaluated per config by the generator-expression evaluator.
        .public_defines = &.{"BUILD_MODE=$<IF:$<CONFIG:Debug>,debug,release>"},
        // target_link_options: drop unreferenced sections at link time.
        .link_options = &.{.{ .gc_sections = true }},
        .configs = zaza.config_sets.debug_only,
    }).buildWithTarget(b, target) catch @panic("orchestration example: build failed");

    const run = b.addRunArtifact(exe);

    // The phony target aggregates the run under a named step.
    _ = zaza.addPhonyTarget(b, .{
        .name = "orchestration-run",
        .description = "Build and run the orchestration example",
        .depends_on = &.{&run.step},
    });

    const build_step = b.step("orchestration", "Build the orchestration example");
    build_step.dependOn(&exe.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    addSteps(b, target);
}
