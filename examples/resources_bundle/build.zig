const std = @import("std");
const zaza = @import("../../build_lib/zaza.zig");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const exe = b.addExecutable(.{
        .name = "resources_bundle_demo",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addCSourceFiles(.{
        .files = &.{"examples/resources_bundle/src/main.cpp"},
        .flags = &.{"-std=c++17"},
    });
    exe.root_module.link_libcpp = true;

    const install_exe = b.addInstallArtifact(exe, .{});
    const asset_rel = "share/resources_bundle/message.txt";
    const copy_asset = zaza.addFileCopies(
        b,
        "resources-bundle",
        &.{
            .{
                .source_path = "examples/resources_bundle/assets/message.txt",
                .dest_path = asset_rel,
                .step_name = "resources-bundle-copy-message",
            },
        },
        &install_exe.step,
    ).?;

    const build_step = b.step("resources-bundle", "Build the resources bundle example");
    build_step.dependOn(copy_asset);

    const run = b.addRunArtifact(exe);
    run.step.dependencies.append(copy_asset) catch unreachable;
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
