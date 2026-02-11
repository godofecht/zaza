const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub var cpp_example = cpp.CppExample{
    .name = "hello_vex_cpp",
    .description = "C++ example built via Vex (Zig build system)",
    .source_files = &.{"examples/hello_vex/src/main.cpp"},
    .include_dirs = &.{},
    .public_include_dirs = &.{"examples/hello_vex/include"},
    .private_include_dirs = &.{},
    .cpp_flags = &.{},
    .public_defines = &.{"HELLO_VEX_PUBLIC=1"},
    .private_defines = &.{"HELLO_VEX_PRIVATE=1"},
    .public_link_libs = &.{},
    .private_link_libs = &.{},
    .deps = &.{},
    .configs = &.{.{ .mode = .Debug }},
    .deps_build_system = .Zig,
    .main_build_system = .Zig,
    .cpp_std = "17",
    .install_headers = &.{"examples/hello_vex/include/hello_vex.h"},
    .export_cmake = true,
};

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    // Zig target (pure Zig)
    const zig_exe = b.addExecutable(.{
        .name = "hello_vex_zig",
        .root_source_file = b.path("examples/hello_vex/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(zig_exe);

    // C++ target (built via Vex)
    const cpp_exe = try cpp_example.buildWithTarget(b, target);
    b.installArtifact(cpp_exe);

    const run_zig = b.addRunArtifact(zig_exe);
    const run_cpp = b.addRunArtifact(cpp_exe);

    const run_step = b.step("run-hello-vex", "Run both hello_vex executables");
    run_step.dependOn(&run_zig.step);
    run_step.dependOn(&run_cpp.step);
}
