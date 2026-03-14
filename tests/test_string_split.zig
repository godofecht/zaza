const std = @import("std");
const testing = std.testing;

test "string split sequence" {
    const repo = "owner/repo@1.0.0";
    
    var parts = std.mem.splitSequence(u8, repo, "@");
    const repo_part = parts.next() orelse return error.InvalidRepo;
    const version = parts.next();  // Optional version tag
    
    try testing.expect(std.mem.eql(u8, repo_part, "owner/repo"));
    try testing.expect(std.mem.eql(u8, version.?, "1.0.0"));
    
    var repo_parts = std.mem.splitSequence(u8, repo_part, "/");
    _ = repo_parts.next() orelse return error.InvalidRepo;  // owner
    const name = repo_parts.next() orelse return error.InvalidRepo;
    
    try testing.expect(std.mem.eql(u8, name, "repo"));
}
