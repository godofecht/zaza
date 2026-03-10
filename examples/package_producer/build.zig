const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub var library = cpp.CppExample{
    .name = "package_math",
    .description = "Reusable package producer library with install/export metadata",
    .kind = .static_library,
    .source_files = &.{"examples/package_producer/src/package_math.cpp"},
    .include_dirs = &.{},
    .public_include_dirs = &.{"examples/package_producer/include"},
    .cpp_flags = &.{},
    .install_headers = &.{"examples/package_producer/include/package_math.hpp"},
    .export_cmake = true,
    .deps = &.{},
    .configs = &.{.{ .mode = .Debug }},
    .deps_build_system = .Zig,
    .main_build_system = .Zig,
    .cpp_std = "17",
};

pub const BuildResult = struct {
    lib: *std.Build.Step.Compile,
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !BuildResult {
    const lib = try library.buildWithTarget(b, target);

    const demo = b.addExecutable(.{
        .name = "package_producer_demo",
        .target = target,
        .optimize = optimize,
    });
    demo.addCSourceFiles(.{
        .files = &.{"examples/package_producer/src/demo.cpp"},
        .flags = &.{"-std=c++17"},
    });
    demo.addIncludePath(b.path("examples/package_producer/include"));
    demo.linkLibCpp();
    demo.linkLibrary(lib);

    const build_step = b.step("package-producer", "Build and install the package producer example");
    build_step.dependOn(&b.addInstallArtifact(lib, .{}).step);
    build_step.dependOn(&b.addInstallArtifact(demo, .{}).step);

    const run = b.addRunArtifact(demo);
    const run_step = b.step("package-producer-run", "Run the package producer demo");
    run_step.dependOn(&run.step);

    return .{
        .lib = lib,
        .build_step = build_step,
        .run_step = run_step,
    };
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = try addSteps(b, target, optimize);
}
