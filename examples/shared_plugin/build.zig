const std = @import("std");
const zaza = @import("../../build_lib/zaza.zig");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const plugin = b.addLibrary(.{
        .name = "shared_plugin",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });
    plugin.root_module.addCSourceFiles(.{
        .files = &.{"examples/shared_plugin/src/plugin.cpp"},
        .flags = &.{"-std=c++17"},
    });
    plugin.root_module.link_libcpp = true;

    const host = b.addExecutable(.{
        .name = "shared_plugin_host",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    host.root_module.addCSourceFiles(.{
        .files = &.{"examples/shared_plugin/src/host.cpp"},
        .flags = &.{"-std=c++17"},
    });
    host.root_module.link_libcpp = true;

    switch (target.result.os.tag) {
        .linux, .freebsd, .netbsd, .openbsd, .dragonfly => host.root_module.linkSystemLibrary("dl", .{}),
        else => {},
    }

    const install_plugin = b.addInstallArtifact(plugin, .{});
    const install_host = b.addInstallArtifact(host, .{});
    const copy_plugin = zaza.addArtifactCopies(
        b,
        "shared-plugin",
        plugin,
        &.{.{ .dest_dir = "share/shared_plugin/plugins", .step_name = "shared-plugin-copy-plugin" }},
        &install_plugin.step,
    ).?;

    const build_step = b.step("shared-plugin", "Build the shared plugin example");
    build_step.dependOn(copy_plugin);
    build_step.dependOn(&install_host.step);

    const run = b.addRunArtifact(host);
    run.step.dependencies.append(copy_plugin) catch unreachable;
    run.addArg(copiedPluginPath(b, target.result.os.tag));
    const run_step = b.step("shared-plugin-run", "Run the shared plugin example");
    run_step.dependOn(&run.step);

    return .{
        .build_step = build_step,
        .run_step = run_step,
    };
}

fn copiedPluginPath(b: *std.Build, os_tag: std.Target.Os.Tag) []const u8 {
    const basename = switch (os_tag) {
        .windows => "shared_plugin.dll",
        .macos => "libshared_plugin.dylib",
        else => "libshared_plugin.so",
    };
    return b.pathJoin(&.{ "zig-out", "share", "shared_plugin", "plugins", basename });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, target, optimize);
}
