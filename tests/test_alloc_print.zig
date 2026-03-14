const std = @import("std");
const testing = std.testing;

test "allocPrint basic" {
    const url = try std.fmt.allocPrint(testing.allocator, "https://github.com/{s}", .{"owner/repo"});
    defer testing.allocator.free(url);
    
    try testing.expect(std.mem.startsWith(u8, url, "https://github.com/"));
    try testing.expect(std.mem.endsWith(u8, url, "owner/repo"));
}

test "allocPrint version" {
    const rev = try std.fmt.allocPrint(testing.allocator, "v{s}", .{"1.0.0"});
    defer testing.allocator.free(rev);
    
    try testing.expect(std.mem.eql(u8, rev, "v1.0.0"));
}
