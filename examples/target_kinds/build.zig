const std = @import("std");
const zaza = @import("../../build_lib/cpp_example.zig");

// Exercises every Zaza library TargetKind through the public API — static,
// shared, object, and interface — plus an executable consumer, so the example
// matrix covers all of them (zaza#41).
const srcs = &[_][]const u8{"examples/target_kinds/src/math_kinds.c"};
const inc = &[_][]const u8{"examples/target_kinds/include"};

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    var static_lib = zaza.CppExample.staticLibrary(.{
        .name = "math_static",
        .source_files = srcs,
        .public_include_dirs = inc,
        .c_std = "11",
    });
    var shared_lib = zaza.CppExample.sharedLibrary(.{
        .name = "math_shared",
        .source_files = srcs,
        .public_include_dirs = inc,
        .c_std = "11",
    });
    var object_lib = zaza.CppExample.objectLibrary(.{
        .name = "math_object",
        .source_files = srcs,
        .public_include_dirs = inc,
        .c_std = "11",
    });
    // Interface library: usage requirements only (an include dir + a define),
    // nothing compiled — the header-only case.
    var iface_lib = zaza.CppExample.interfaceLibrary(.{
        .name = "math_iface",
        .source_files = &.{},
        .public_include_dirs = inc,
        .public_defines = &.{"MATH_KINDS_IFACE=1"},
    });

    const sl = try static_lib.buildWithTarget(b, target);
    const shl = try shared_lib.buildWithTarget(b, target);
    const ol = try object_lib.buildWithTarget(b, target);
    _ = try iface_lib.buildWithTarget(b, target);

    const exe = b.addExecutable(.{
        .name = "target_kinds_app",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize }),
    });
    exe.root_module.addCSourceFiles(.{ .files = &.{"examples/target_kinds/src/main.c"}, .flags = &.{"-std=c11"} });
    exe.root_module.addIncludePath(b.path("examples/target_kinds/include"));
    exe.root_module.link_libc = true;
    exe.root_module.linkLibrary(sl);

    const build_step = b.step("target-kinds", "Build every Zaza library kind + a consumer");
    build_step.dependOn(&b.addInstallArtifact(sl, .{}).step);
    build_step.dependOn(&b.addInstallArtifact(shl, .{}).step);
    // An object library has no install procedure; depend on its compile step so
    // it is built (proving the kind), just not installed.
    build_step.dependOn(&ol.step);
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("target-kinds-run", "Build and run the target-kinds example");
    run_step.dependOn(&run.step);
}
