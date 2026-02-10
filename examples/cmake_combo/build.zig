const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub var example = cpp.CppExample{
    .name = "cmake_combo",
    .description = "CMake deps (fmt + spdlog) with Zig-built executable",
    .source_files = &.{"examples/cmake_combo/src/main.cpp"},
    .include_dirs = &.{
        "zig-out/deps/include",
    },
    .cpp_flags = &.{},
    .deps = &.{
        .{
            .name = "fmt",
            .url = "https://github.com/fmtlib/fmt.git",
            .type = .CMake,
            .cmake_config = .{
                .install_prefix = "zig-out/deps",
                .install = true,
                .configure_args = &.{
                    "-DFMT_DOC=OFF",
                    "-DFMT_TEST=OFF",
                    "-DFMT_INSTALL=ON",
                },
            },
        },
        .{
            .name = "spdlog",
            .url = "https://github.com/gabime/spdlog.git",
            .type = .CMake,
            .cmake_config = .{
                .install_prefix = "zig-out/deps",
                .install = true,
                .configure_args = &.{
                    "-DSPDLOG_BUILD_EXAMPLES=OFF",
                    "-DSPDLOG_BUILD_TESTS=OFF",
                    "-DSPDLOG_FMT_EXTERNAL=ON",
                    "-DSPDLOG_INSTALL=ON",
                    "-DCMAKE_PREFIX_PATH=zig-out/deps",
                },
            },
        },
    },
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

pub fn buildWithTarget(b: *std.Build, target: std.Build.ResolvedTarget) !*std.Build.Step.Compile {
    return example.buildWithTarget(b, target);
}

pub fn build(b: *std.Build) !*std.Build.Step.Compile {
    const target = b.standardTargetOptions(.{});
    return buildWithTarget(b, target);
}
