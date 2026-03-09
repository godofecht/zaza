const std = @import("std");
const testing = std.testing;
const presets = @import("presets");

test "asan preset enables sanitizer flags" {
    const configs = presets.presetConfigs("asan");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(@as(usize, 1), configs[0].cpp_flags.len);
    try testing.expectEqualStrings("-fsanitize=address", configs[0].cpp_flags[0]);
}

test "lto preset enables lto" {
    const configs = presets.presetConfigs("lto");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expect(configs[0].want_lto);
}
