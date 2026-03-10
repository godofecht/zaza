const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const exe = b.addExecutable(.{
        .name = "resources_bundle_demo",
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{
        .files = &.{"examples/resources_bundle/src/main.cpp"},
        .flags = &.{"-std=c++17"},
    });
    exe.linkLibCpp();

    const install_exe = b.addInstallArtifact(exe, .{});
    const asset_rel = "share/resources_bundle/message.txt";
    const install_asset = b.addInstallFileWithDir(
        b.path("examples/resources_bundle/assets/message.txt"),
        .prefix,
        asset_rel,
    );

    const build_step = b.step("resources-bundle", "Build the resources bundle example");
    build_step.dependOn(&install_exe.step);
    build_step.dependOn(&install_asset.step);

    const run = b.addRunArtifact(exe);
    run.step.dependencies.append(&install_asset.step) catch unreachable;
    run.addArg(b.pathJoin(&.{ "zig-out", asset_rel }));

    const run_step = b.step("resources-bundle-run", "Run the resources bundle example");
    run_step.dependOn(&run.step);

    return .{
        .build_step = build_step,
        .run_step = run_step,
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, target, optimize);
}
