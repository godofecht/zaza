const std = @import("std");
const testing = std.testing;
const builder = @import("builder");

test "Platform definitions" {
    try testing.expect(builder.Platform.linux_x64.arch == .x86_64);
    try testing.expect(builder.Platform.linux_x64.os == .linux);
    try testing.expect(std.mem.eql(u8, builder.Platform.linux_x64.name, "linux-x64"));
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
}
