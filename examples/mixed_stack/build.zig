const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const c_lib = b.addStaticLibrary(.{
        .name = "mixed_core",
        .target = target,
        .optimize = optimize,
    });
    c_lib.addCSourceFiles(.{
        .files = &.{"examples/mixed_stack/src/mixed_core.c"},
        .flags = &.{"-std=c11"},
    });
    c_lib.addIncludePath(b.path("examples/mixed_stack/include"));

    const cpp_lib = b.addStaticLibrary(.{
        .name = "mixed_bridge",
        .target = target,
        .optimize = optimize,
    });
    cpp_lib.addCSourceFiles(.{
        .files = &.{"examples/mixed_stack/src/mixed_bridge.cpp"},
        .flags = &.{"-std=c++17"},
    });
    cpp_lib.addIncludePath(b.path("examples/mixed_stack/include"));
    cpp_lib.linkLibCpp();
    cpp_lib.linkLibrary(c_lib);

    const exe = b.addExecutable(.{
        .name = "mixed_stack_demo",
        .root_source_file = b.path("examples/mixed_stack/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(c_lib);
    exe.linkLibrary(cpp_lib);
    exe.linkLibCpp();

    const build_step = b.step("mixed-stack", "Build the mixed C + C++ + Zig example");
    build_step.dependOn(&b.addInstallArtifact(c_lib, .{}).step);
    build_step.dependOn(&b.addInstallArtifact(cpp_lib, .{}).step);
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("mixed-stack-run", "Run the mixed C + C++ + Zig example");
    run_step.dependOn(&run.step);

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
