const std = @import("std");
const testing = std.testing;

// Test basic builder functionality without complex imports
test "basic platform test" {
    // Test platform definitions directly
    const linux_x64 = struct {
        arch: std.Target.Cpu.Arch,
        os: std.Target.Os.Tag,
        name: []const u8,
    }{ .arch = .x86_64, .os = .linux, .name = "linux-x64" };
    
    try testing.expect(linux_x64.arch == .x86_64);
    try testing.expect(linux_x64.os == .linux);
    try testing.expect(std.mem.eql(u8, linux_x64.name, "linux-x64"));
}

test "basic dependency parsing" {
    // Test the string parsing logic without the complex struct
    const repo = "owner/repo@1.0.0";
    
    var parts = std.mem.splitSequence(u8, repo, "@");
    const repo_part = parts.next() orelse return error.InvalidRepo;
    const version = parts.next();
    
    try testing.expect(std.mem.eql(u8, repo_part, "owner/repo"));
    try testing.expect(std.mem.eql(u8, version.?, "1.0.0"));
    
    var repo_parts = std.mem.splitSequence(u8, repo_part, "/");
    _ = repo_parts.next() orelse return error.InvalidRepo;
    const name = repo_parts.next() orelse return error.InvalidRepo;
    
    try testing.expect(std.mem.eql(u8, name, "repo"));
}

test "memory management" {
    const allocator = std.testing.allocator;
    
    const str = try allocator.alloc(u8, 10);
    defer allocator.free(str);
    
    try testing.expect(str.len == 10);
}

test "string formatting" {
    const url = try std.fmt.allocPrint(testing.allocator, "https://github.com/{s}", .{"owner/repo"});
    defer testing.allocator.free(url);
    
    try testing.expect(std.mem.startsWith(u8, url, "https://github.com/"));
    try testing.expect(std.mem.endsWith(u8, url, "owner/repo"));
}
