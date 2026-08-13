//! Consuming an installed library through `findPackage`.
//!
//! The same program is built twice against the same installed zlib, once with
//! the library resolved by pkg-config and once by CMake's `find_package(ZLIB)`.
//! Neither the include path nor the library name is written by hand: Zaza asks
//! the real resolver and folds the include dirs and link inputs into the target.
//! This is the "consume the CMake ecosystem" direction.

const std = @import("std");
const zaza = @import("../../build_lib/zaza.zig");

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget) void {
    // Resolver A: pkg-config (zlib ships a zlib.pc on almost every system).
    const zlib_pc = zaza.findPackage(b, "zlib", .{ .prefer = .pkg_config });

    // Resolver B: CMake's own find_package. ZLIB is a builtin Find module and
    // exports the ZLIB::ZLIB imported target; passing it lets Zaza read the
    // target's precise interface properties.
    const zlib_cmake = zaza.findPackage(b, "zlib", .{
        .prefer = .cmake,
        .cmake_name = "ZLIB",
        .cmake_target = "ZLIB::ZLIB",
    });

    const run_pc = addOne(b, target, "find-package-pc", "find_package_pc", zlib_pc);
    const run_cmake = addOne(b, target, "find-package-cmake", "find_package_cmake", zlib_cmake);

    // An aggregate step that builds and runs both.
    const both = b.step("find-package", "Build and run the findPackage example (pkg-config + CMake)");
    both.dependOn(run_pc);
    both.dependOn(run_cmake);
}

fn addOne(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    step_name: []const u8,
    exe_name: []const u8,
    zlib: zaza.ResolvedPackage,
) *std.Build.Step {
    const exe = zaza.Target.executable(.{
        .name = exe_name,
        .description = "links installed zlib resolved by findPackage",
        .source_files = &.{"examples/find_package/src/main.c"},
        .c_std = "11",
        .packages = &.{zlib},
        .configs = zaza.config_sets.debug_only,
    }).buildWithTarget(b, target) catch @panic("find_package example: build failed");

    const run = b.addRunArtifact(exe);
    const run_step = b.step(b.fmt("{s}-run", .{step_name}), b.fmt("Run {s}", .{exe_name}));
    run_step.dependOn(&run.step);

    const build_step = b.step(step_name, b.fmt("Build {s}", .{exe_name}));
    build_step.dependOn(&exe.step);
    return run_step;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    addSteps(b, target);
}
