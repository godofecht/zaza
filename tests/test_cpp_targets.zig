const std = @import("std");
const testing = std.testing;
const cpp = @import("cpp_example");

test "usage requirements merge" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const left = cpp.UsageRequirements{
        .include_dirs = &.{"include/core"},
        .compile_definitions = &.{"CORE=1"},
    };
    const right = cpp.UsageRequirements{
        .include_dirs = &.{"include/extra"},
        .link_libraries = &.{"fmt"},
    };

    const merged = try left.merge(allocator, right);
    try testing.expectEqual(@as(usize, 2), merged.include_dirs.len);
    try testing.expectEqualStrings("include/core", merged.include_dirs[0]);
    try testing.expectEqualStrings("include/extra", merged.include_dirs[1]);
    try testing.expectEqual(@as(usize, 1), merged.compile_definitions.len);
    try testing.expectEqual(@as(usize, 1), merged.link_libraries.len);
}

test "public dependencies propagate exported usage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const graph = [_]cpp.CppTarget{
        .{
            .name = "core",
            .kind = .static_library,
            .include_dirs = .{
                .include_dirs = &.{"core/include"},
                .compile_definitions = &.{"CORE_API=1"},
            },
        },
        .{
            .name = "app",
            .kind = .executable,
            .include_dirs = .{
                .include_dirs = &.{"app/include"},
            },
            .dependencies = &.{
                .{ .name = "core", .visibility = .public },
            },
        },
    };

    const resolved = try graph[1].resolveUsage(allocator, &graph);
    try testing.expectEqual(@as(usize, 2), resolved.local.include_dirs.len);
    try testing.expectEqualStrings("app/include", resolved.local.include_dirs[0]);
    try testing.expectEqualStrings("core/include", resolved.local.include_dirs[1]);
    try testing.expectEqual(@as(usize, 2), resolved.exported.include_dirs.len);
    try testing.expectEqual(@as(usize, 1), resolved.link_libraries.len);
    try testing.expectEqualStrings("core", resolved.link_libraries[0]);
}

test "private dependencies stay local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const graph = [_]cpp.CppTarget{
        .{
            .name = "logging",
            .kind = .interface_library,
            .include_dirs = .{
                .compile_definitions = &.{"LOGGING=1"},
            },
        },
        .{
            .name = "lib",
            .kind = .static_library,
            .dependencies = &.{
                .{ .name = "logging", .visibility = .private },
            },
        },
    };

    const resolved = try graph[1].resolveUsage(allocator, &graph);
    try testing.expectEqual(@as(usize, 1), resolved.local.compile_definitions.len);
    try testing.expectEqual(@as(usize, 0), resolved.exported.compile_definitions.len);
}

test "interface dependencies export usage without local link" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const graph = [_]cpp.CppTarget{
        .{
            .name = "warnings",
            .kind = .interface_library,
            .include_dirs = .{
                .compile_options = &.{"-Wall"},
            },
        },
        .{
            .name = "sdk",
            .kind = .interface_library,
            .dependencies = &.{
                .{ .name = "warnings", .visibility = .interface },
            },
        },
    };

    const resolved = try graph[1].resolveUsage(allocator, &graph);
    try testing.expectEqual(@as(usize, 0), resolved.local.compile_options.len);
    try testing.expectEqual(@as(usize, 1), resolved.exported.compile_options.len);
}

test "object and interface usage propagates through public static library" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const graph = [_]cpp.CppTarget{
        .{
            .name = "graph_interface",
            .kind = .interface_library,
            .include_dirs = .{
                .include_dirs = &.{"graph/include"},
                .compile_definitions = &.{"GRAPH_API_LEVEL=4"},
            },
        },
        .{
            .name = "graph_objects",
            .kind = .object_library,
            .dependencies = &.{
                .{ .name = "graph_interface", .visibility = .public },
            },
        },
        .{
            .name = "graph_core",
            .kind = .static_library,
            .dependencies = &.{
                .{ .name = "graph_interface", .visibility = .public },
                .{ .name = "graph_objects", .visibility = .private },
            },
        },
        .{
            .name = "graph_app",
            .kind = .executable,
            .dependencies = &.{
                .{ .name = "graph_core", .visibility = .public },
            },
        },
    };

    const resolved = try graph[3].resolveUsage(allocator, &graph);
    try testing.expectEqual(@as(usize, 1), resolved.local.include_dirs.len);
    try testing.expectEqualStrings("graph/include", resolved.local.include_dirs[0]);
    try testing.expectEqual(@as(usize, 1), resolved.local.compile_definitions.len);
    try testing.expectEqualStrings("GRAPH_API_LEVEL=4", resolved.local.compile_definitions[0]);
    try testing.expectEqual(@as(usize, 1), resolved.link_libraries.len);
    try testing.expectEqualStrings("graph_core", resolved.link_libraries[0]);
}

test "all source files include generated sources" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const example = cpp.CppExample{
        .name = "generated_demo",
        .description = "test",
        .source_files = &.{"src/main.cpp"},
        .generated_source_files = &.{"zig-out/gen/generated.cpp"},
        .include_dirs = &.{},
        .cpp_flags = &.{},
        .deps = &.{},
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = .Zig,
        .main_build_system = .Zig,
        .cpp_std = "17",
    };

    const files = try example.allSourceFiles(arena.allocator());
    try testing.expectEqual(@as(usize, 2), files.len);
    try testing.expectEqualStrings("src/main.cpp", files[0]);
    try testing.expectEqualStrings("zig-out/gen/generated.cpp", files[1]);
}

test "c_std selects a C target; default targets stay C++" {
    // A C target carries its C standard and leaves cpp_std unused.
    const c_target = cpp.CppExample.executable(.{
        .name = "c_app",
        .source_files = &.{"src/main.c"},
        .c_std = "99",
    });
    try testing.expect(c_target.c_std != null);
    try testing.expectEqualStrings("99", c_target.c_std.?);

    // A default target has no c_std, so it builds as C++.
    const cpp_target = cpp.CppExample.executable(.{
        .name = "cpp_app",
        .source_files = &.{"src/main.cpp"},
    });
    try testing.expectEqual(@as(?[]const u8, null), cpp_target.c_std);
    try testing.expectEqualStrings("17", cpp_target.cpp_std.?);
}

test "unity source includes every source by absolute path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const text = try cpp.unitySourceText(
        arena.allocator(),
        "app",
        "/root",
        &.{ "src/a.cpp", "src/b.cpp" },
    );
    try testing.expect(std.mem.indexOf(u8, text, "#include \"/root/src/a.cpp\"") != null);
    try testing.expect(std.mem.indexOf(u8, text, "#include \"/root/src/b.cpp\"") != null);
    // The generated banner names the target.
    try testing.expect(std.mem.indexOf(u8, text, "unity build: app") != null);
}
