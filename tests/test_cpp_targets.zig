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
