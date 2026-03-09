const std = @import("std");
const cpp = @import("cpp_example.zig");

pub fn presetConfigs(preset: []const u8) []const cpp.BuildConfig {
    if (std.ascii.eqlIgnoreCase(preset, "debug")) {
        return &.{.{ .mode = .Debug }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "release")) {
        return &.{.{ .mode = .Release }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "asan")) {
        return &.{.{ .mode = .Debug, .cpp_flags = &.{"-fsanitize=address"}, .defines = &.{"VEX_ASAN=1"} }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "lto")) {
        return &.{.{ .mode = .Release, .want_lto = true, .defines = &.{"VEX_LTO=1"} }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "relwithdebinfo")) {
        return &.{.{ .mode = .RelWithDebInfo }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "minsizerel")) {
        return &.{.{ .mode = .MinSizeRel }};
    }
    return &.{.{ .mode = .Debug }};
}
