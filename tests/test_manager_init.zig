const std = @import("std");
const testing = std.testing;
const deps = @import("dependencies");

test "DependencyManager init only" {
    var manager = deps.DependencyManager.init(testing.allocator);
    defer manager.deinit();
    
    try testing.expect(manager.dependencies.items.len == 0);
    try testing.expect(manager.cmake_paths.items.len == 0);
    try testing.expect(std.mem.eql(u8, manager.deps_dir, "deps"));
    try testing.expect(std.mem.eql(u8, manager.workspace_root, "."));
}
