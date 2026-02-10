const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub var example = cpp.CppExample{
    .name = "cmake_net",
    .description = "CMake deps (curl + zlib + mbedtls) with Zig-built executable",
    .source_files = &.{"examples/cmake_net/src/main.cpp"},
    .include_dirs = &.{
        "zig-out/deps/include",
    },
    .cpp_flags = &.{},
    .deps = &.{
        .{
            .name = "zlib",
            .url = "https://github.com/madler/zlib.git",
            .type = .CMake,
            .cmake_config = .{
                .install_prefix = "zig-out/deps",
                .install = true,
                .configure_args = &.{
                    "-DZLIB_BUILD_EXAMPLES=OFF",
                    "-DZLIB_BUILD_TESTS=OFF",
                    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                },
            },
        },
        .{
            .name = "mbedtls",
            .url = "https://github.com/Mbed-TLS/mbedtls.git",
            .type = .CMake,
            .cmake_config = .{
                .install_prefix = "zig-out/deps",
                .install = true,
                .configure_args = &.{
                    "-DENABLE_PROGRAMS=OFF",
                    "-DENABLE_TESTING=OFF",
                    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                },
            },
        },
        .{
            .name = "curl",
            .url = "https://github.com/curl/curl.git",
            .type = .CMake,
            .cmake_config = .{
                .install_prefix = "zig-out/deps",
                .install = true,
                .configure_args = &.{
                    "-DBUILD_SHARED_LIBS=OFF",
                    "-DBUILD_TESTING=OFF",
                    "-DCURL_USE_MBEDTLS=ON",
                    "-DCURL_ZLIB=ON",
                    "-DHTTP_ONLY=ON",
                    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                    "-DCMAKE_PREFIX_PATH=zig-out/deps",
                },
            },
        },
    },
    .configs = &.{.{
        .mode = .Debug,
        .system_includes = &.{"zig-out/deps/include"},
        .link_paths = &.{"zig-out/deps/lib"},
        .link_libs = &.{"curl", "z", "mbedtls", "mbedx509", "mbedcrypto"},
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
