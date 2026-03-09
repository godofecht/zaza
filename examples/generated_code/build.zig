const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub var example = cpp.CppExample{
    .name = "generated_code_demo",
    .description = "Generated source example",
    .source_files = &.{"examples/generated_code/src/main.cpp"},
    .generated_source_files = &.{"zig-out/gen/generated_message.cpp"},
    .include_dirs = &.{"zig-out/gen"},
    .cpp_flags = &.{},
    .custom_commands = &.{
        .{
            .name = "generate_generated_message",
            .argv = &.{"sh", "examples/generated_code/scripts/generate_message.sh", "zig-out/gen/generated_message.cpp"},
        },
    },
    .deps = &.{},
    .configs = &.{.{ .mode = .Debug }},
    .deps_build_system = .Zig,
    .main_build_system = .Zig,
    .cpp_std = "17",
    .enable_system_commands = true,
};

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, _: std.builtin.OptimizeMode) !void {
    const exe = try example.buildWithTarget(b, target);

    const build_step = b.step("generated-code", "Build the generated source example");
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("generated-code-run", "Run the generated source example");
    run_step.dependOn(&run.step);
}
