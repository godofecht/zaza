const std = @import("std");
const rust_example = @import("../../build_lib/rust_example.zig");

pub const BuildResult = rust_example.RustExample.BuildResult;

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const rust = rust_example.RustExample{
        .name = "rust_math",
        .crate_dir = "examples/rust_interop/rust_lib",
    };

    return rust.addSteps(
        b,
        target,
        optimize,
        "examples/rust_interop/src/main.zig",
        "rust_interop_demo",
    );
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, target, optimize);
}
