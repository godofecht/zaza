//! The test workflow example, declared through the first-class test API.
//!
//! Before, this file hand-wired an executable and three run steps, each with its
//! own name, cwd, env var, and argument, then assembled the aggregate and
//! per-mode steps by hand. Now the three modes are data: one `RunCase` each,
//! passed to `test_suite.addTest`. The API produces the same steps
//! (`test-workflows`, `test-workflows-run`, and one `test-workflows-<mode>` per
//! case) and hooks the aggregate onto the top `test` step.

const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");
const test_suite = @import("../../build_lib/test_suite.zig");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    _ = optimize;

    const demo = cpp.CppExample.executable(.{
        .name = "test_workflows_demo",
        .description = "Workflow example driven by the first-class test API",
        .source_files = &.{"examples/test_workflows/src/main.cpp"},
        .cpp_std = "17",
    });

    const cwd = b.path("examples/test_workflows");

    const result = test_suite.addTest(b, target, .{
        .name = "test-workflows",
        .target = demo,
        .cases = &.{
            .{
                .label = "unit",
                .args = &.{"unit"},
                .env = &.{.{ .name = "WORKFLOW_MODE", .value = "unit" }},
                .cwd = cwd,
            },
            .{
                .label = "integration",
                .args = &.{"integration"},
                .env = &.{.{ .name = "WORKFLOW_MODE", .value = "integration" }},
                .cwd = cwd,
            },
            .{
                .label = "smoke",
                .args = &.{"smoke"},
                .env = &.{.{ .name = "WORKFLOW_MODE", .value = "smoke" }},
                .cwd = cwd,
            },
        },
    }) catch @panic("failed to declare test-workflows suite");

    return .{
        .build_step = result.build_step,
        .run_step = result.run_step,
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, target, optimize);
}
