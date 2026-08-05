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

test "tsan preset has sanitizer flags and define" {
    const configs = presets.presetConfigs("tsan");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .Debug);
    try testing.expectEqual(@as(usize, 1), configs[0].cpp_flags.len);
    try testing.expectEqualStrings("-fsanitize=thread", configs[0].cpp_flags[0]);
    try testing.expectEqual(@as(usize, 1), configs[0].defines.len);
    try testing.expectEqualStrings("ZAZA_TSAN=1", configs[0].defines[0]);
}

test "ubsan preset has sanitizer flags and define" {
    const configs = presets.presetConfigs("ubsan");
    try testing.expectEqual(@as(usize, 1), configs.len);
    try testing.expectEqual(configs[0].mode, .Debug);
    try testing.expectEqual(@as(usize, 1), configs[0].cpp_flags.len);
    try testing.expectEqualStrings("-fsanitize=undefined", configs[0].cpp_flags[0]);
    try testing.expectEqual(@as(usize, 1), configs[0].defines.len);
    try testing.expectEqualStrings("ZAZA_UBSAN=1", configs[0].defines[0]);
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

test "resolvePresetWithAllocator reads zaza-presets.json custom presets" {
    const json_content =
        \\{
        \\  "presets": {
        \\    "my-custom-debug": [
        \\      {
        \\        "mode": "Debug",
        \\        "defines": ["CUSTOM_DEBUG_FLAG=1"],
        \\        "cpp_flags": ["-Wall"]
        \\      }
        \\    ],
        \\    "my-custom-release": [
        \\      {
        \\        "mode": "Release",
        \\        "want_lto": true
        \\      }
        \\    ]
        \\  }
        \\}
    ;

    // Write to a temporary presets file
    const compat = presets.compat;
    try compat.writeFile(compat.io(), "zaza-presets.json", json_content);
    defer {
        if (comptime compat.has_io) {
            std.Io.Dir.cwd().deleteFile(compat.io(), "zaza-presets.json") catch {};
        } else {
            std.fs.cwd().deleteFile("zaza-presets.json") catch {};
        }
    }

    const configs_debug = presets.resolvePresetWithAllocator(testing.allocator, "my-custom-debug");
    defer {
        for (configs_debug) |cfg| {
            for (cfg.defines) |def| testing.allocator.free(def);
            testing.allocator.free(cfg.defines);
            for (cfg.cpp_flags) |flag| testing.allocator.free(flag);
            testing.allocator.free(cfg.cpp_flags);
            for (cfg.system_includes) |inc| testing.allocator.free(inc);
            testing.allocator.free(cfg.system_includes);
            for (cfg.link_paths) |path| testing.allocator.free(path);
            testing.allocator.free(cfg.link_paths);
            for (cfg.link_files) |file| testing.allocator.free(file);
            testing.allocator.free(cfg.link_files);
            for (cfg.link_frameworks) |fw| testing.allocator.free(fw);
            testing.allocator.free(cfg.link_frameworks);
            for (cfg.link_libs) |lib| testing.allocator.free(lib);
            testing.allocator.free(cfg.link_libs);
        }
        testing.allocator.free(configs_debug);
    }

    try testing.expectEqual(@as(usize, 1), configs_debug.len);
    try testing.expectEqual(configs_debug[0].mode, .Debug);
    try testing.expectEqual(@as(usize, 1), configs_debug[0].defines.len);
    try testing.expectEqualStrings("CUSTOM_DEBUG_FLAG=1", configs_debug[0].defines[0]);
    try testing.expectEqual(@as(usize, 1), configs_debug[0].cpp_flags.len);
    try testing.expectEqualStrings("-Wall", configs_debug[0].cpp_flags[0]);

    // Also test case-insensitive match on the custom preset
    const configs_release = presets.resolvePresetWithAllocator(testing.allocator, "MY-CUSTOM-RELEASE");
    defer {
        for (configs_release) |cfg| {
            for (cfg.defines) |def| testing.allocator.free(def);
            testing.allocator.free(cfg.defines);
            for (cfg.cpp_flags) |flag| testing.allocator.free(flag);
            testing.allocator.free(cfg.cpp_flags);
            for (cfg.system_includes) |inc| testing.allocator.free(inc);
            testing.allocator.free(cfg.system_includes);
            for (cfg.link_paths) |path| testing.allocator.free(path);
            testing.allocator.free(cfg.link_paths);
            for (cfg.link_files) |file| testing.allocator.free(file);
            testing.allocator.free(cfg.link_files);
            for (cfg.link_frameworks) |fw| testing.allocator.free(fw);
            testing.allocator.free(cfg.link_frameworks);
            for (cfg.link_libs) |lib| testing.allocator.free(lib);
            testing.allocator.free(cfg.link_libs);
        }
        testing.allocator.free(configs_release);
    }

    try testing.expectEqual(@as(usize, 1), configs_release.len);
    try testing.expectEqual(configs_release[0].mode, .Release);
    try testing.expect(configs_release[0].want_lto);
}

test "release preset has no extra flags" {
    const configs = presets.presetConfigs("release");
    try testing.expectEqual(@as(usize, 0), configs[0].cpp_flags.len);
    try testing.expect(!configs[0].want_lto);
}
