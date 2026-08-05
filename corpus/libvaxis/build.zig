const std = @import("std");

// A pure-Zig corpus slice. libvaxis has no C or C++ sources, so Zaza's C/C++
// target DSL (zaza.Target) does not apply — and does not need to. Zaza is a Zig
// build system, so a Zig library is consumed with the standard Zig build graph
// that Zaza is built on. This build file is exactly what a Zaza user writes for
// a Zig dependency: declare it, import its module, run a consumer.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vaxis = b.dependency("vaxis", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "vaxis_consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("vaxis", vaxis.module("vaxis"));
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "Build the vaxis consumer and run it");
    run_step.dependOn(&run.step);
}
