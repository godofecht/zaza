const std = @import("std");
const testing = std.testing;
const presets = @import("presets");

test "debug preset returns Debug mode" {
    const configs = presets.presetConfigs("debug");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .Debug);
}

test "release preset returns Release mode" {
    const configs = presets.presetConfigs("release");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .Release);
}

test "asan preset has sanitizer flags and define" {
    const configs = presets.presetConfigs("asan");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .Debug);
    try testing.expectEqual(@as(usize, 1), configs[0].cpp_flags.len);
    try testing.expectEqualStrings("-fsanitize=address", configs[0].cpp_flags[0]);
    try testing.expectEqual(@as(usize, 1), configs[0].defines.len);
    try testing.expectEqualStrings("ZAZA_ASAN=1", configs[0].defines[0]);
}

test "lto preset enables link-time optimization" {
    const configs = presets.presetConfigs("lto");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .Release);
    try testing.expect(configs[0].want_lto);
    try testing.expectEqual(@as(usize, 1), configs[0].defines.len);
    try testing.expectEqualStrings("ZAZA_LTO=1", configs[0].defines[0]);
}

test "relwithdebinfo preset" {
    const configs = presets.presetConfigs("relwithdebinfo");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .RelWithDebInfo);
}

test "minsizerel preset" {
    const configs = presets.presetConfigs("minsizerel");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .MinSizeRel);
}

test "unknown preset falls back to Debug" {
    const configs = presets.presetConfigs("nonexistent");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .Debug);
}

test "preset names are case insensitive" {
    const lower = presets.presetConfigs("asan");
    const upper = presets.presetConfigs("ASAN");
    const mixed = presets.presetConfigs("Asan");

    try testing.expectEqual(lower[0].mode, upper[0].mode);
    try testing.expectEqual(lower[0].mode, mixed[0].mode);
    try testing.expectEqual(lower[0].cpp_flags.len, upper[0].cpp_flags.len);
    try testing.expectEqual(lower[0].cpp_flags.len, mixed[0].cpp_flags.len);
}

test "debug preset has no extra flags" {
    const configs = presets.presetConfigs("debug");
    try testing.expectEqual(@as(usize, 0), configs[0].cpp_flags.len);
    try testing.expect(!configs[0].want_lto);
}

test "release preset has no extra flags" {
    const configs = presets.presetConfigs("release");
    try testing.expectEqual(@as(usize, 0), configs[0].cpp_flags.len);
    try testing.expect(!configs[0].want_lto);
}
