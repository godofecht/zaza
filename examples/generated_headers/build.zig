const std = @import("std");
const vex_cmd = @import("../../build_lib/vex_cmd.zig");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const gen_header = "zig-out/gen/generated_message.hpp";
    const generate_header = vex_cmd.addCommandStep(
        b,
        "generate_generated_header",
        &.{ "sh", "examples/generated_headers/scripts/generate_header.sh", gen_header },
    );

    const lib = b.addStaticLibrary(.{
        .name = "generated_headers_lib",
        .target = target,
        .optimize = optimize,
    });
    lib.addCSourceFiles(.{
        .files = &.{"examples/generated_headers/src/generated_greeter.cpp"},
        .flags = &.{"-std=c++17"},
    });
    lib.addIncludePath(b.path("examples/generated_headers/include"));
    lib.addIncludePath(.{ .cwd_relative = "zig-out/gen" });
    lib.linkLibCpp();
    lib.step.dependencies.append(generate_header) catch unreachable;

    const exe = b.addExecutable(.{
        .name = "generated_headers_demo",
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{
        .files = &.{"examples/generated_headers/src/main.cpp"},
        .flags = &.{"-std=c++17"},
    });
    exe.addIncludePath(b.path("examples/generated_headers/include"));
    exe.addIncludePath(.{ .cwd_relative = "zig-out/gen" });
    exe.linkLibCpp();
    exe.linkLibrary(lib);
    exe.step.dependencies.append(generate_header) catch unreachable;

    const build_step = b.step("generated-headers", "Build the generated header example");
    build_step.dependOn(&b.addInstallArtifact(lib, .{}).step);
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("generated-headers-run", "Run the generated header example");
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
