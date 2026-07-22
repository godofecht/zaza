const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const lib = b.addLibrary(.{
        .name = "calculator_bindings",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    lib.root_module.addCSourceFiles(.{
        .files = &.{
            "examples/bindings/src/calculator.cpp",
            "examples/bindings/src/calculator_wrapper.cpp",
        },
        .flags = &.{"-std=c++20"},
    });
    lib.root_module.addIncludePath(b.path("examples/bindings/src"));
    lib.root_module.link_libcpp = true;

    const exe = b.addExecutable(.{
        .name = "bindings_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/bindings/zig/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("calculator", b.createModule(.{
        .root_source_file = b.path("examples/bindings/zig/calculator.zig"),
    }));
    exe.root_module.linkLibrary(lib);
    exe.root_module.link_libcpp = true;

    const build_step = b.step("bindings", "Build the Zig-to-C++ bindings example");
    build_step.dependOn(&b.addInstallArtifact(lib, .{}).step);
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("bindings-run", "Run the Zig-to-C++ bindings example");
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
