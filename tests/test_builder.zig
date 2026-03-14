const std = @import("std");
const testing = std.testing;
const builder = @import("builder");

test "Platform definitions" {
    try testing.expect(builder.Platform.linux_x64.arch == .x86_64);
    try testing.expect(builder.Platform.linux_x64.os == .linux);
    try testing.expect(std.mem.eql(u8, builder.Platform.linux_x64.name, "linux-x64"));
    
    try testing.expect(builder.Platform.windows_x64.arch == .x86_64);
    try testing.expect(builder.Platform.windows_x64.os == .windows);
    try testing.expect(std.mem.eql(u8, builder.Platform.windows_x64.name, "windows-x64"));
    
    try testing.expect(builder.Platform.macos_arm64.arch == .aarch64);
    try testing.expect(builder.Platform.macos_arm64.os == .macos);
    try testing.expect(std.mem.eql(u8, builder.Platform.macos_arm64.name, "macos-arm64"));
    
    try testing.expect(builder.Platform.wasm.arch == .wasm32);
    try testing.expect(builder.Platform.wasm.os == .wasi);
    try testing.expect(std.mem.eql(u8, builder.Platform.wasm.name, "wasm"));
}

test "Platform.target" {
    const platform = builder.Platform.macos_x64;
    const target = platform.target();
    
    try testing.expect(target.cpu_arch == .x86_64);
    try testing.expect(target.os_tag == .macos);
}

test "Platform arrays" {
    try testing.expect(builder.Platform.desktop.len == 4);
    try testing.expect(builder.Platform.all.len == 6);
    
    // Check that desktop platforms are indeed desktop platforms
    for (builder.Platform.desktop) |platform| {
        try testing.expect(platform.os == .linux or platform.os == .windows or platform.os == .macos);
    }
}

test "Example struct" {
    const example = builder.Example{
        .name = "test",
        .description = "test description",
        .source_files = &.{"main.cpp"},
        .platforms = &.{builder.Platform.macos_x64},
        .dependencies = &.{},
        .cpp_standard = "20",
        .defines = &.{"TEST=1"},
        .include_paths = &.{"include"},
    };
    
    try testing.expect(std.mem.eql(u8, example.name, "test"));
    try testing.expect(std.mem.eql(u8, example.description, "test description"));
    try testing.expect(example.source_files.len == 1);
    try testing.expect(example.platforms.len == 1);
    try testing.expect(example.dependencies.len == 0);
    try testing.expect(std.mem.eql(u8, example.cpp_standard, "20"));
    try testing.expect(example.defines.len == 1);
    try testing.expect(example.include_paths.len == 1);
}
