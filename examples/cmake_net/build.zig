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
            .git_ref = "v1.3.1",
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
            .git_ref = "v3.6.2",
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
            .git_ref = "curl-8_6_0",
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
        .link_files = &.{
            "zig-out/deps/lib/libcurl.a",
            "zig-out/deps/lib/libz.a",
            "zig-out/deps/lib/libmbedtls.a",
            "zig-out/deps/lib/libmbedx509.a",
            "zig-out/deps/lib/libtfpsacrypto.a",
        },
        .link_libs = &.{"z", "pthread"},
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
