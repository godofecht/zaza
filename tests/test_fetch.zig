const std = @import("std");
const testing = std.testing;
const deps = @import("dependencies");

test "fetchLatest basic" {
    var manager = deps.DependencyManager.init(testing.allocator);
    defer manager.deinit();
    
    const dep1 = try manager.fetchLatest("owner/repo");
    defer testing.allocator.free(dep1.url);
    defer testing.allocator.free(dep1.rev);
    defer testing.allocator.free(dep1.name);
    if (dep1.cmake_package) |pkg| testing.allocator.free(pkg);
    if (dep1.include_path) |path| testing.allocator.free(path);
    
    try testing.expect(std.mem.eql(u8, dep1.name, "repo"));
    try testing.expect(std.mem.eql(u8, dep1.rev, "main"));
}
