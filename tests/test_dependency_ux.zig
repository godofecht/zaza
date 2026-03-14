const std = @import("std");
const testing = std.testing;
const cpp = @import("cpp_example");
const zaza = @import("zaza_cli");

test "parse dependency names from zon" {
    const zon =
        \\.{
        \\    .dependencies = .{
        \\        .fmt = .{
        \\            .url = "https://example.com/fmt.tar.gz",
        \\        },
        \\        .spdlog = .{
        \\            .url = "https://example.com/spdlog.tar.gz",
        \\        },
        \\    },
        \\}
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const names = try zaza.parseDependencyNames(arena.allocator(), zon);

    try testing.expectEqual(@as(usize, 2), names.len);
    try testing.expectEqualStrings("fmt", names[0]);
    try testing.expectEqualStrings("spdlog", names[1]);
}

test "update and remove lock entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zaza.lock", .data = "{\n  \"packages\": {}\n}\n" });
    const cwd = std.fs.cwd();
    var old_cwd = try cwd.openDir(".", .{});
    defer old_cwd.close();
    try tmp.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try zaza.updateLock(allocator, "zaza.lock", "fmt", "https://example.com/fmt.tar.gz", "hash123");
    var lock = try zaza.readFile(allocator, "zaza.lock");
    try testing.expect(std.mem.indexOf(u8, lock, "\"fmt\"") != null);
    try testing.expect(std.mem.indexOf(u8, lock, "\"source\": \"registry\"") != null);

    try zaza.removeLockEntry(allocator, "zaza.lock", "fmt");
    lock = try zaza.readFile(allocator, "zaza.lock");
    try testing.expect(std.mem.indexOf(u8, lock, "\"fmt\"") == null);
}

test "package manifest includes exported metadata" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const example = cpp.CppExample{
        .name = "hello_zaza_cpp",
        .description = "test",
        .kind = .static_library,
        .source_files = &.{"src/main.cpp"},
        .include_dirs = &.{},
        .public_include_dirs = &.{"include"},
        .cpp_flags = &.{},
        .public_link_libs = &.{"fmt"},
        .install_headers = &.{"include/hello_zaza.h"},
        .install_libs = &.{"libhello_zaza.a"},
        .deps = &.{},
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = .Zig,
        .main_build_system = .Zig,
        .cpp_std = "17",
    };

    const manifest = try cpp.buildPackageManifest(allocator, example);
    try testing.expect(std.mem.indexOf(u8, manifest, "\"kind\": \"static_library\"") != null);
    try testing.expect(std.mem.indexOf(u8, manifest, "\"include_dirs\": [\"include/hello_zaza_cpp\"]") != null);
    try testing.expect(std.mem.indexOf(u8, manifest, "\"libs\": [\"lib/libhello_zaza_cpp_Debug.a\", \"lib/libhello_zaza.a\"]") != null);
    try testing.expect(std.mem.indexOf(u8, manifest, "\"link_libraries\": [\"fmt\"]") != null);
}

test "dependency sync script checks out requested git ref" {
    const dep = cpp.Dependency{
        .name = "mbedtls",
        .url = "https://github.com/Mbed-TLS/mbedtls.git",
        .git_ref = "mbedtls-3.6.2",
    };

    const script = cpp.dependencySyncScript(testing.allocator, dep, false);
    defer testing.allocator.free(script);
    try testing.expect(std.mem.indexOf(u8, script, "git -C deps/mbedtls checkout --force mbedtls-3.6.2") != null);
    try testing.expect(std.mem.indexOf(u8, script, "git clone --depth 1 --branch mbedtls-3.6.2") != null);
}
