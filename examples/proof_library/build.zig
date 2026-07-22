const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub var library = cpp.CppExample.staticLibrary(.{
    .name = "proof_math",
    .description = "Proof library example with install/export metadata",
    .source_files = &.{"examples/proof_library/src/proof_math.cpp"},
    .public_include_dirs = &.{"examples/proof_library/include"},
    .install_headers = &.{"examples/proof_library/include/proof_math.hpp"},
    .export_cmake = true,
    .cpp_std = "17",
});

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    const lib = try library.buildWithTarget(b, target);

    const exe = b.addExecutable(.{
        .name = "proof_library_app",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addCSourceFiles(.{
        .files = &.{"examples/proof_library/src/main.cpp"},
        .flags = &.{"-std=c++17"},
    });
    exe.root_module.addIncludePath(b.path("examples/proof_library/include"));
    exe.root_module.link_libcpp = true;
    exe.root_module.linkLibrary(lib);

    const build_step = b.step("proof-library", "Build the proof library example");
    build_step.dependOn(&b.addInstallArtifact(lib, .{}).step);
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("proof-library-run", "Run the proof library example");
    run_step.dependOn(&run.step);
}
