const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const exe = b.addExecutable(.{
        .name = "benchmark_workflow_demo",
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{
        .files = &.{"examples/benchmark_workflow/src/main.cpp"},
        .flags = &.{"-std=c++17"},
    });
    exe.linkLibCpp();

    const install = b.addInstallArtifact(exe, .{});
    const build_step = b.step("benchmark-workflow", "Build the benchmark workflow example");
    build_step.dependOn(&install.step);

    const bench = b.addRunArtifact(exe);
    bench.setName("benchmark-run");
    bench.addArg("750000");

    const run_step = b.step("benchmark-workflow-run", "Run the benchmark workflow example");
    run_step.dependOn(&bench.step);

    const quick = b.addRunArtifact(exe);
    quick.setName("benchmark-quick");
    quick.addArg("100000");

    const quick_step = b.step("benchmark-workflow-quick", "Run a quick benchmark workflow example");
    quick_step.dependOn(&quick.step);

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
