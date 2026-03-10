const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub var example = cpp.CppExample{
    .name = "preset_profiles_demo",
    .description = "Preset profile example showing debug/release/asan/lto modes",
    .source_files = &.{"examples/preset_profiles/src/main.cpp"},
    .include_dirs = &.{},
    .cpp_flags = &.{},
    .deps = &.{},
    .configs = &.{.{ .mode = .Debug }},
    .deps_build_system = .Zig,
    .main_build_system = .Zig,
    .cpp_std = "17",
};

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, _: std.builtin.OptimizeMode) !void {
    const exe = try example.buildWithTarget(b, target);

    const build_step = b.step("preset-profiles", "Build the preset profile example");
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("preset-profiles-run", "Run the preset profile example");
    run_step.dependOn(&run.step);
}
