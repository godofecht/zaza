const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const exe = b.addExecutable(.{
        .name = "test_workflows_demo",
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{
        .files = &.{"examples/test_workflows/src/main.cpp"},
        .flags = &.{"-std=c++17"},
    });
    exe.linkLibCpp();

    const build_step = b.step("test-workflows", "Build the workflow example");
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const unit_run = b.addRunArtifact(exe);
    unit_run.setName("workflow-unit");
    unit_run.setCwd(b.path("examples/test_workflows"));
    unit_run.setEnvironmentVariable("WORKFLOW_MODE", "unit");
    unit_run.addArg("unit");

    const integration_run = b.addRunArtifact(exe);
    integration_run.setName("workflow-integration");
    integration_run.setCwd(b.path("examples/test_workflows"));
    integration_run.setEnvironmentVariable("WORKFLOW_MODE", "integration");
    integration_run.addArg("integration");

    const smoke_run = b.addRunArtifact(exe);
    smoke_run.setName("workflow-smoke");
    smoke_run.setCwd(b.path("examples/test_workflows"));
    smoke_run.setEnvironmentVariable("WORKFLOW_MODE", "smoke");
    smoke_run.addArg("smoke");

    const run_step = b.step("test-workflows-run", "Run all workflow example modes");
    run_step.dependOn(&unit_run.step);
    run_step.dependOn(&integration_run.step);
    run_step.dependOn(&smoke_run.step);

    const unit_step = b.step("test-workflows-unit", "Run workflow example unit mode");
    unit_step.dependOn(&unit_run.step);

    const integration_step = b.step("test-workflows-integration", "Run workflow example integration mode");
    integration_step.dependOn(&integration_run.step);

    return .{
        .build_step = build_step,
        .run_step = run_step,
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, target, optimize);
}
