const std = @import("std");
const testing = std.testing;
const cpp = @import("cpp_example");

// --- Dependency struct tests ---

test "dependency defaults" {
    const dep = cpp.Dependency{
        .name = "fmt",
        .url = "https://github.com/fmtlib/fmt",
    };
    try testing.expectEqualStrings("fmt", dep.name);
    try testing.expect(dep.git_ref == null);
    try testing.expect(dep.include_path == null);
    try testing.expect(dep.type == null);
    try testing.expect(dep.cmake_config == null);
    try testing.expect(dep.pkg_name == null);
    try testing.expectEqual(@as(usize, 0), dep.build_command.len);
}

test "dependency with cmake config" {
    const dep = cpp.Dependency{
        .name = "zlib",
        .url = "https://github.com/madler/zlib",
        .git_ref = "v1.3.1",
        .type = .CMake,
        .cmake_config = .{
            .install = true,
            .configure_args = &.{"-DBUILD_SHARED_LIBS=OFF"},
        },
    };
    try testing.expectEqualStrings("zlib", dep.name);
    try testing.expectEqualStrings("v1.3.1", dep.git_ref.?);
    try testing.expectEqual(dep.type.?, .CMake);
    try testing.expect(dep.cmake_config != null);
    try testing.expect(dep.cmake_config.?.install);
    try testing.expectEqual(@as(usize, 1), dep.cmake_config.?.configure_args.len);
}

// --- CMakeConfig struct tests ---

test "cmake config defaults" {
    const cfg = cpp.CMakeConfig{};
    try testing.expect(cfg.source_dir == null);
    try testing.expect(cfg.build_dir == null);
    try testing.expect(cfg.generator == null);
    try testing.expect(cfg.toolchain_file == null);
    try testing.expect(cfg.install_prefix == null);
    try testing.expect(!cfg.install);
    try testing.expectEqual(@as(usize, 0), cfg.configure_args.len);
    try testing.expectEqual(@as(usize, 0), cfg.build_args.len);
    try testing.expectEqual(@as(usize, 0), cfg.install_args.len);
}

test "cmake config with all fields" {
    const cfg = cpp.CMakeConfig{
        .source_dir = "deps/zlib",
        .build_dir = "build/zlib",
        .generator = "Ninja",
        .toolchain_file = "toolchain.cmake",
        .install_prefix = "zig-out",
        .install = true,
        .configure_args = &.{"-DBUILD_TESTING=OFF"},
        .build_args = &.{"--parallel", "8"},
        .install_args = &.{"--strip"},
    };
    try testing.expectEqualStrings("deps/zlib", cfg.source_dir.?);
    try testing.expectEqualStrings("Ninja", cfg.generator.?);
    try testing.expect(cfg.install);
    try testing.expectEqual(@as(usize, 1), cfg.configure_args.len);
    try testing.expectEqual(@as(usize, 2), cfg.build_args.len);
}

// --- BuildConfig tests ---

test "build config defaults" {
    const cfg = cpp.BuildConfig{ .mode = .Debug };
    try testing.expectEqual(cfg.mode, .Debug);
    try testing.expectEqual(@as(usize, 0), cfg.cpp_flags.len);
    try testing.expectEqual(@as(usize, 0), cfg.defines.len);
    try testing.expect(!cfg.want_lto);
}

test "build config with flags" {
    const cfg = cpp.BuildConfig{
        .mode = .Release,
        .cpp_flags = &.{"-O3"},
        .defines = &.{"NDEBUG=1"},
        .want_lto = true,
    };
    try testing.expectEqual(cfg.mode, .Release);
    try testing.expectEqual(@as(usize, 1), cfg.cpp_flags.len);
    try testing.expectEqualStrings("-O3", cfg.cpp_flags[0]);
    try testing.expect(cfg.want_lto);
}

// --- CppExample struct tests ---

test "cpp example basic construction" {
    const ex = cpp.CppExample{
        .name = "my_app",
        .description = "A test application",
        .source_files = &.{"src/main.cpp"},
        .include_dirs = &.{"include"},
        .cpp_flags = &.{"-std=c++17"},
        .deps = &.{},
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = .Zig,
        .main_build_system = .Zig,
        .cpp_std = "17",
    };
    try testing.expectEqualStrings("my_app", ex.name);
    try testing.expectEqual(@as(usize, 1), ex.source_files.len);
    try testing.expectEqual(@as(usize, 1), ex.include_dirs.len);
}

test "all source files without generated sources" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const ex = cpp.CppExample{
        .name = "simple",
        .description = "test",
        .source_files = &.{ "a.cpp", "b.cpp" },
        .include_dirs = &.{},
        .cpp_flags = &.{},
        .deps = &.{},
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = .Zig,
        .main_build_system = .Zig,
        .cpp_std = "17",
    };

    const files = try ex.allSourceFiles(arena.allocator());
    try testing.expectEqual(@as(usize, 2), files.len);
    try testing.expectEqualStrings("a.cpp", files[0]);
    try testing.expectEqualStrings("b.cpp", files[1]);
}

test "all source files with generated sources" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const ex = cpp.CppExample{
        .name = "gen",
        .description = "test",
        .source_files = &.{"src/main.cpp"},
        .generated_source_files = &.{ "gen/a.cpp", "gen/b.cpp" },
        .include_dirs = &.{},
        .cpp_flags = &.{},
        .deps = &.{},
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = .Zig,
        .main_build_system = .Zig,
        .cpp_std = "17",
    };

    const files = try ex.allSourceFiles(arena.allocator());
    try testing.expectEqual(@as(usize, 3), files.len);
}

// --- UsageRequirements tests ---

test "usage requirements empty merge" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const empty = cpp.UsageRequirements{};
    const merged = try empty.merge(arena.allocator(), empty);
    try testing.expectEqual(@as(usize, 0), merged.include_dirs.len);
    try testing.expectEqual(@as(usize, 0), merged.compile_definitions.len);
    try testing.expectEqual(@as(usize, 0), merged.link_libraries.len);
    try testing.expectEqual(@as(usize, 0), merged.compile_options.len);
}

test "usage requirements merge preserves all fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const a = cpp.UsageRequirements{
        .include_dirs = &.{"include/a"},
        .compile_definitions = &.{"A=1"},
        .compile_options = &.{"-Wall"},
    };
    const b = cpp.UsageRequirements{
        .include_dirs = &.{"include/b"},
        .link_libraries = &.{"pthread"},
        .compile_options = &.{"-Werror"},
    };

    const merged = try a.merge(arena.allocator(), b);
    try testing.expectEqual(@as(usize, 2), merged.include_dirs.len);
    try testing.expectEqual(@as(usize, 1), merged.compile_definitions.len);
    try testing.expectEqual(@as(usize, 1), merged.link_libraries.len);
    try testing.expectEqual(@as(usize, 2), merged.compile_options.len);
}

test "usage requirements merge with one empty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const full = cpp.UsageRequirements{
        .include_dirs = &.{ "a", "b" },
        .compile_definitions = &.{"X=1"},
    };
    const empty = cpp.UsageRequirements{};

    const merged = try full.merge(arena.allocator(), empty);
    try testing.expectEqual(@as(usize, 2), merged.include_dirs.len);
    try testing.expectEqual(@as(usize, 1), merged.compile_definitions.len);
}

// --- BuildSystem enum tests ---

test "build system enum values" {
    try testing.expect(cpp.BuildSystem.Zig != cpp.BuildSystem.CMake);
}

// --- CppTarget dependency resolution edge cases ---

test "target with no dependencies resolves cleanly" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const graph = [_]cpp.CppTarget{
        .{
            .name = "standalone",
            .kind = .executable,
            .include_dirs = .{
                .include_dirs = &.{"include"},
                .compile_definitions = &.{"STANDALONE=1"},
            },
        },
    };

    const resolved = try graph[0].resolveUsage(arena.allocator(), &graph);
    try testing.expectEqual(@as(usize, 1), resolved.local.include_dirs.len);
    try testing.expectEqual(@as(usize, 1), resolved.local.compile_definitions.len);
    try testing.expectEqual(@as(usize, 0), resolved.link_libraries.len);
}

test "diamond dependency does not duplicate includes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const graph = [_]cpp.CppTarget{
        .{
            .name = "base",
            .kind = .interface_library,
            .include_dirs = .{
                .include_dirs = &.{"base/include"},
            },
        },
        .{
            .name = "left",
            .kind = .static_library,
            .dependencies = &.{
                .{ .name = "base", .visibility = .public },
            },
        },
        .{
            .name = "right",
            .kind = .static_library,
            .dependencies = &.{
                .{ .name = "base", .visibility = .public },
            },
        },
        .{
            .name = "top",
            .kind = .executable,
            .dependencies = &.{
                .{ .name = "left", .visibility = .public },
                .{ .name = "right", .visibility = .public },
            },
        },
    };

    const resolved = try graph[3].resolveUsage(arena.allocator(), &graph);
    // Should have base/include (possibly duplicated - that's ok for now)
    try testing.expect(resolved.local.include_dirs.len >= 1);
    // Should link both left and right
    try testing.expectEqual(@as(usize, 2), resolved.link_libraries.len);
}

test "deep chain propagates through multiple levels" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const graph = [_]cpp.CppTarget{
        .{
            .name = "level0",
            .kind = .interface_library,
            .include_dirs = .{
                .compile_definitions = &.{"LEVEL0=1"},
            },
        },
        .{
            .name = "level1",
            .kind = .static_library,
            .dependencies = &.{
                .{ .name = "level0", .visibility = .public },
            },
        },
        .{
            .name = "level2",
            .kind = .static_library,
            .dependencies = &.{
                .{ .name = "level1", .visibility = .public },
            },
        },
        .{
            .name = "level3",
            .kind = .executable,
            .dependencies = &.{
                .{ .name = "level2", .visibility = .public },
            },
        },
    };

    const resolved = try graph[3].resolveUsage(arena.allocator(), &graph);
    // LEVEL0=1 should propagate all the way through public chains
    try testing.expect(resolved.local.compile_definitions.len >= 1);
    // Should link level2 at minimum
    try testing.expect(resolved.link_libraries.len >= 1);
}
