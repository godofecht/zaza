const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub const Artifacts = struct {
    zig_exe: *std.Build.Step.Compile,
    cpp_exe: *std.Build.Step.Compile,
};

pub var cpp_example = cpp.CppExample{
    .name = "hello_zaza_cpp",
    .description = "C++ example built via Zaza (Zig build system)",
    .source_files = &.{"examples/hello_zaza/src/main.cpp"},
    .include_dirs = &.{},
    .public_include_dirs = &.{"examples/hello_zaza/include"},
    .private_include_dirs = &.{},
    .cpp_flags = &.{},
    .public_defines = &.{"HELLO_ZAZA_PUBLIC=1"},
    .private_defines = &.{"HELLO_ZAZA_PRIVATE=1"},
    .public_link_libs = &.{},
    .private_link_libs = &.{},
    .deps = &.{},
    .configs = &.{.{ .mode = .Debug }},
    .deps_build_system = .Zig,
    .main_build_system = .Zig,
    .cpp_std = "17",
    .install_headers = &.{"examples/hello_zaza/include/hello_zaza.h"},
    .export_cmake = true,
};

pub fn addArtifacts(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !Artifacts {
    // Zig target (pure Zig)
    const zig_exe = b.addExecutable(.{
        .name = "hello_zaza_zig",
        .root_source_file = b.path("examples/hello_zaza/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // C++ target (built via Zaza)
    const cpp_exe = try cpp_example.buildWithTarget(b, target);

    return .{
        .zig_exe = zig_exe,
        .cpp_exe = cpp_exe,
    };
}

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    const artifacts = try addArtifacts(b, target, optimize);
    b.installArtifact(artifacts.zig_exe);
    b.installArtifact(artifacts.cpp_exe);

    const run_zig = b.addRunArtifact(artifacts.zig_exe);
    const run_cpp = b.addRunArtifact(artifacts.cpp_exe);

    const run_step = b.step("run-hello-zaza", "Run both hello_zaza executables");
    run_step.dependOn(&run_zig.step);
    run_step.dependOn(&run_cpp.step);
}
