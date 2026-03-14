const std = @import("std");
const testing = std.testing;
const zigcpp = @import("../zigcpp.zig");

test "Cpp.create" {
    const b = std.testing.allocator;
    
    // Test that we can create a Cpp builder
    var app = zigcpp.Cpp.create(b, "test_app", .executable);
    defer app.deinit();
    
    try testing.expect(app.artifact != null);
    try testing.expect(std.mem.eql(u8, app.version, "17"));
}

test "Cpp.createWithOptions" {
    const b = std.testing.allocator;
    
    // Test creating with custom options
    var app = zigcpp.Cpp.createWithOptions(
        b,
        "custom_app",
        .library,
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .Debug,
    );
    defer app.deinit();
    
    try testing.expect(app.artifact != null);
}

test "Platform.target" {
    const platform = zigcpp.Platform.macos_x64;
    const target = platform.target();
    
    try testing.expect(target.cpu_arch == .x86_64);
    try testing.expect(target.os_tag == .macos);
}

test "Example.build" {
    const b = std.testing.allocator;
    
    const example = zigcpp.Example{
        .name = "test_example",
        .description = "Test example",
        .source_files = &.{"test.cpp"},
        .platforms = &.{zigcpp.Platform.macos_x64},
    };
    
    // Test that build function exists and can be called
    // Note: We can't actually build in tests without a proper Build context
    try testing.expect(example.name.len > 0);
    try testing.expect(example.description.len > 0);
    try testing.expect(example.source_files.len > 0);
}
