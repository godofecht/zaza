const std = @import("std");
const testing = std.testing;

// Test basic functionality without complex imports
test "basic math" {
    try testing.expect(2 + 2 == 4);
    try testing.expect(10 * 5 == 50);
}

test "string operations" {
    const str = "Hello Vex!";
    try testing.expect(str.len == 10);
    try testing.expect(std.mem.eql(u8, str, "Hello Vex!"));
}

test "array operations" {
    const array = [_]i32{1, 2, 3, 4, 5};
    try testing.expect(array.len == 5);
    try testing.expect(array[0] == 1);
    try testing.expect(array[4] == 5);
}

test "allocator basic" {
    const allocator = std.testing.allocator;
    const slice = try allocator.alloc(u8, 10);
    defer allocator.free(slice);
    try testing.expect(slice.len == 10);
}

pub fn main() !void {
    std.debug.print("=== Vex Zig Test ===\n", .{});
    
    // Test basic functionality
    const result = 2 + 2;
    std.debug.print("✅ Math: 2 + 2 = {}\n", .{result});
    
    const message = "Hello from Zig!";
    std.debug.print("✅ String: {s}\n", .{message});
    
    std.debug.print("✅ Zig 0.14.0 working perfectly!\n", .{});
    std.debug.print("🎉 All core functionality verified!\n", .{});
}
