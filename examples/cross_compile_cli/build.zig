const std = @import("std");

pub fn build(b: *std.Build) !void {
    const triple = b.option([]const u8, "target-triple", "Target triple to cross compile") orelse "x86_64-linux-musl";
    const query = std.Build.parseTargetQuery(.{ .arch_os_abi = triple }) catch
        @panic("invalid target triple for cross_compile_cli");
    const target = b.resolveTargetQuery(query);
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "cross_compile_cli",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const build_step = b.step("cross-compile-cli", "Build the cross compile CLI example");
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
}
