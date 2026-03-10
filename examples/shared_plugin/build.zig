const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const plugin = b.addSharedLibrary(.{
        .name = "shared_plugin",
        .target = target,
        .optimize = optimize,
    });
    plugin.addCSourceFiles(.{
        .files = &.{"examples/shared_plugin/src/plugin.cpp"},
        .flags = &.{"-std=c++17"},
    });
    plugin.linkLibCpp();

    const host = b.addExecutable(.{
        .name = "shared_plugin_host",
        .target = target,
        .optimize = optimize,
    });
    host.addCSourceFiles(.{
        .files = &.{"examples/shared_plugin/src/host.cpp"},
        .flags = &.{"-std=c++17"},
    });
    host.linkLibCpp();

    switch (target.result.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly => host.linkSystemLibrary("dl"),
        else => {},
    }

    const install_plugin = b.addInstallArtifact(plugin, .{});
    const install_host = b.addInstallArtifact(host, .{});

    const build_step = b.step("shared-plugin", "Build the shared plugin example");
    build_step.dependOn(&install_plugin.step);
    build_step.dependOn(&install_host.step);

    const run = b.addRunArtifact(host);
    run.step.dependencies.append(&install_plugin.step) catch unreachable;
    run.addArg(installedPluginPath(b, target.result.os.tag));
    const run_step = b.step("shared-plugin-run", "Run the shared plugin example");
    run_step.dependOn(&run.step);

    return .{
        .build_step = build_step,
        .run_step = run_step,
    };
}

fn installedPluginPath(b: *std.Build, os_tag: std.Target.Os.Tag) []const u8 {
    const basename = switch (os_tag) {
        .windows => "shared_plugin.dll",
        .macos => "libshared_plugin.dylib",
        else => "libshared_plugin.so",
    };
    return b.pathJoin(&.{ "zig-out", "lib", basename });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, target, optimize);
}
