const std = @import("std");
const cpp = @import("build_lib/cpp_example.zig");

pub const example = cpp.CppExample{
    .name = "json_example",
    .description = "JSON example using nlohmann/json",
    .source_files = &.{"src/main.cpp",},
    .include_dirs = &.{"deps/json/single_include",},
    .cpp_flags = &.{"-D_HAS_EXCEPTIONS=1",},
    .deps = &.{
        .{ .name = "json", .url = "https://github.com/nlohmann/json.git", .type = .Zig },
    },
    .configs = &.{.{ .mode = .Debug }},
    .deps_build_system = .Zig,
    .main_build_system = .Zig,
    .cpp_std = "17",
};

pub fn build(b: *std.Build) !void {
    const exe = try example.build(b);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    // Add view step to show configuration UI
    const view_step = b.step("view", "View and edit build configuration");
    const server_cmd = b.addSystemCommand(&.{
        "zig", "run", "-lc", "build_lib/server.zig", "--",
        try std.json.stringifyAlloc(b.allocator, example, .{}),
    });
    view_step.dependOn(&server_cmd.step);
}
