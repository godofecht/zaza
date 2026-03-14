const std = @import("std");
const testing = std.testing;

const Dependency = struct {
    url: []const u8,
    rev: []const u8,
    name: []const u8,
    cmake_package: ?[]const u8 = null,
    subdirectory: ?[]const u8 = null,
    include_path: ?[]const u8 = null,
};

test "minimal fetch" {
    const repo = "owner/repo";
    
    // Parse repo format: "owner/name[@version]"
    var parts = std.mem.splitSequence(u8, repo, "@");
    const repo_part = parts.next() orelse return error.InvalidRepo;
    const version = parts.next();  // Optional version tag

    var repo_parts = std.mem.splitSequence(u8, repo_part, "/");
    _ = repo_parts.next() orelse return error.InvalidRepo;  // owner
    const name = repo_parts.next() orelse return error.InvalidRepo;

    const rev = if (version) |v| 
        try std.fmt.allocPrint(testing.allocator, "v{s}", .{v}) 
    else 
        "main";
    
    const url = try std.fmt.allocPrint(testing.allocator, "https://github.com/{s}", .{repo_part});
    defer testing.allocator.free(url);
    
    const dep = Dependency{
        .url = url,
        .rev = rev,
        .name = name,
        .cmake_package = if (std.mem.eql(u8, name, "json")) "nlohmann_json" else null,
        .include_path = if (std.mem.eql(u8, name, "json")) "single_include" else null,
    };
    
    try testing.expect(std.mem.eql(u8, dep.name, "repo"));
    try testing.expect(std.mem.eql(u8, dep.rev, "main"));
}
