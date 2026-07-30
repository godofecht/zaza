const std = @import("std");
const cpp = @import("cpp_example.zig");

/// Resolve a preset name to a build configuration list. Known names are
/// `debug`, `release`, `relwithdebinfo`, `minsizerel`, `asan`, and `lto`; the
/// match is case-insensitive. An unknown name falls back to debug. This is what
/// `ZAZA_PRESET` selects.
pub fn presetConfigs(preset: []const u8) []const cpp.BuildConfig {
    if (std.ascii.eqlIgnoreCase(preset, "debug")) {
        return &.{.{ .mode = .Debug }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "release")) {
        return &.{.{ .mode = .Release }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "asan")) {
        return &.{.{ .mode = .Debug, .cpp_flags = &.{"-fsanitize=address"}, .defines = &.{"ZAZA_ASAN=1"} }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "lto")) {
        return &.{.{ .mode = .Release, .want_lto = true, .defines = &.{"ZAZA_LTO=1"} }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "relwithdebinfo")) {
        return &.{.{ .mode = .RelWithDebInfo }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "minsizerel")) {
        return &.{.{ .mode = .MinSizeRel }};
    }
    return &.{.{ .mode = .Debug }};
}
