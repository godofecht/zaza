const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub var example = cpp.CppExample{
    .name = "cmake_shim",
    .description = "CMake shim example using nlohmann/json",
    .source_files = &.{"src/main.cpp"},
    .include_dirs = &.{"deps/json/single_include"},
    .cpp_flags = &.{"-D_HAS_EXCEPTIONS=1"},
    .deps = &.{
        .{
            .name = "json",
            .url = "https://github.com/nlohmann/json.git",
            .type = .CMake,
            .cmake_config = .{
                .configure_args = &.{"-DJSON_BuildTests=OFF", "-DJSON_Install=OFF"},
                .install = true,
                .install_prefix = "zig-out/deps",
            },
        },
    },
    .configs = &.{.{ .mode = .Debug }},
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
