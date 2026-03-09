const std = @import("std");
const testing = std.testing;
const cpp = @import("cpp_example");

test "tooling manifest includes config-specific paths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const example = cpp.CppExample{
        .name = "cmake_combo",
        .description = "test",
        .source_files = &.{"examples/cmake_combo/src/main.cpp"},
        .include_dirs = &.{"zig-out/deps/include"},
        .public_include_dirs = &.{"include/public"},
        .cpp_flags = &.{},
        .public_defines = &.{"FMT_SHARED=1"},
        .private_defines = &.{"SPDLOG_FMT_EXTERNAL=1"},
        .deps = &.{},
        .configs = &.{.{
            .mode = .Debug,
            .system_includes = &.{"zig-out/deps/include"},
            .link_paths = &.{"zig-out/deps/lib"},
            .link_libs = &.{"fmt", "spdlog"},
        }},
        .deps_build_system = .CMake,
        .main_build_system = .Zig,
        .cpp_std = "17",
    };

    const manifest = try cpp.buildToolingManifest(
        allocator,
        example,
        example.configs[0],
        "Debug",
        "compile_commands.json",
        example.public_include_dirs,
        &.{},
        example.include_dirs,
        example.public_defines,
        example.private_defines,
    );

    try testing.expect(std.mem.indexOf(u8, manifest, "\"config\": \"Debug\"") != null);
    try testing.expect(std.mem.indexOf(u8, manifest, "\"link_paths\": [\"zig-out/deps/lib\"]") != null);
    try testing.expect(std.mem.indexOf(u8, manifest, "\"link_libs\": [\"fmt\", \"spdlog\"]") != null);
}
