const std = @import("std");
const cpp = @import("cpp_example.zig");
pub const compat = @import("compat.zig");

pub fn resolvePreset(b: *std.Build, preset: []const u8) []const cpp.BuildConfig {
    return resolvePresetWithAllocator(b.allocator, preset);
}

pub fn resolvePresetWithAllocator(allocator: std.mem.Allocator, preset: []const u8) []const cpp.BuildConfig {
    const paths = [_][]const u8{ "zaza-presets.local.json", "zaza-presets.json" };
    for (paths) |path| {
        if (readAndParsePreset(allocator, path, preset)) |configs| {
            return configs;
        }
    }
    return presetConfigs(preset);
}

fn readAndParsePreset(allocator: std.mem.Allocator, path: []const u8, preset_name: []const u8) ?[]const cpp.BuildConfig {
    const content = compat.readFile(compat.io(), allocator, path) orelse return null;
    defer allocator.free(content);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return null;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return null;

    const presets_val = root.object.get("presets") orelse return null;
    if (presets_val != .object) return null;

    var preset_entry_opt: ?std.json.Value = null;
    var it = presets_val.object.iterator();
    while (it.next()) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, preset_name)) {
            preset_entry_opt = entry.value_ptr.*;
            break;
        }
    }

    const preset_entry = preset_entry_opt orelse return null;
    if (preset_entry != .array) return null;

    var configs: std.ArrayListUnmanaged(cpp.BuildConfig) = .empty;
    errdefer configs.deinit(allocator);

    for (preset_entry.array.items) |config_val| {
        if (config_val != .object) return null;
        const mode_str_val = config_val.object.get("mode") orelse return null;
        if (mode_str_val != .string) return null;

        var mode: cpp.BuildMode = .Debug;
        if (std.ascii.eqlIgnoreCase(mode_str_val.string, "Debug")) {
            mode = .Debug;
        } else if (std.ascii.eqlIgnoreCase(mode_str_val.string, "Release")) {
            mode = .Release;
        } else if (std.ascii.eqlIgnoreCase(mode_str_val.string, "RelWithDebInfo")) {
            mode = .RelWithDebInfo;
        } else if (std.ascii.eqlIgnoreCase(mode_str_val.string, "MinSizeRel")) {
            mode = .MinSizeRel;
        } else {
            return null;
        }

        const target = if (config_val.object.get("target")) |v| (if (v == .string) allocator.dupe(u8, v.string) catch null else null) else null;
        const want_lto = if (config_val.object.get("want_lto")) |v| (if (v == .bool) v.bool else false) else false;

        const defines = parseStringArray(allocator, config_val.object.get("defines")) orelse &.{};
        const cpp_flags = parseStringArray(allocator, config_val.object.get("cpp_flags")) orelse &.{};
        const system_includes = parseStringArray(allocator, config_val.object.get("system_includes")) orelse &.{};
        const link_paths = parseStringArray(allocator, config_val.object.get("link_paths")) orelse &.{};
        const link_files = parseStringArray(allocator, config_val.object.get("link_files")) orelse &.{};
        const link_frameworks = parseStringArray(allocator, config_val.object.get("link_frameworks")) orelse &.{};
        const link_libs = parseStringArray(allocator, config_val.object.get("link_libs")) orelse &.{};

        configs.append(allocator, .{
            .mode = mode,
            .target = target,
            .defines = defines,
            .cpp_flags = cpp_flags,
            .system_includes = system_includes,
            .link_paths = link_paths,
            .link_files = link_files,
            .link_frameworks = link_frameworks,
            .link_libs = link_libs,
            .want_lto = want_lto,
        }) catch return null;
    }

    return configs.toOwnedSlice(allocator) catch null;
}

fn parseStringArray(allocator: std.mem.Allocator, val_opt: ?std.json.Value) ?[]const []const u8 {
    const val = val_opt orelse return null;
    if (val != .array) return null;
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer list.deinit(allocator);
    for (val.array.items) |item| {
        if (item != .string) return null;
        const duped = allocator.dupe(u8, item.string) catch return null;
        list.append(allocator, duped) catch return null;
    }
    return list.toOwnedSlice(allocator) catch return null;
}

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
    if (std.ascii.eqlIgnoreCase(preset, "tsan")) {
        return &.{.{ .mode = .Debug, .cpp_flags = &.{"-fsanitize=thread"}, .defines = &.{"ZAZA_TSAN=1"} }};
    }
    if (std.ascii.eqlIgnoreCase(preset, "ubsan")) {
        return &.{.{ .mode = .Debug, .cpp_flags = &.{"-fsanitize=undefined"}, .defines = &.{"ZAZA_UBSAN=1"} }};
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
