const std = @import("std");
const testing = std.testing;
const deps = @import("dependencies");

test "DependencyManager initialization" {
    var manager = deps.DependencyManager.init(std.testing.allocator);
    defer manager.deinit();

    try testing.expect(manager.dependencies.items.len == 0);
    try testing.expect(manager.cmake_paths.items.len == 0);
    try testing.expect(std.mem.eql(u8, manager.deps_dir, "deps"));
    try testing.expect(std.mem.eql(u8, manager.workspace_root, "."));
}

test "DependencyManager initWithPaths" {
    const allocator = std.testing.allocator;
    var manager = deps.DependencyManager.initWithPaths(allocator, "custom_deps", "workspace");
    defer manager.deinit();
    
    try testing.expect(std.mem.eql(u8, manager.deps_dir, "custom_deps"));
    try testing.expect(std.mem.eql(u8, manager.workspace_root, "workspace"));
}

test "Dependency struct" {
    const dep = deps.Dependency{
        .url = "https://github.com/example/test.git",
        .rev = "v1.0.0",
        .name = "test_dep",
        .cmake_package = "TestPackage",
        .subdirectory = "src",
        .include_path = "include",
    };
    
    try testing.expect(std.mem.eql(u8, dep.url, "https://github.com/example/test.git"));
    try testing.expect(std.mem.eql(u8, dep.rev, "v1.0.0"));
    try testing.expect(std.mem.eql(u8, dep.name, "test_dep"));
    try testing.expect(std.mem.eql(u8, dep.cmake_package.?, "TestPackage"));
    try testing.expect(std.mem.eql(u8, dep.subdirectory.?, "src"));
    try testing.expect(std.mem.eql(u8, dep.include_path.?, "include"));
}

test "fetchLatest" {
    const allocator = std.testing.allocator;
    var manager = deps.DependencyManager.init(allocator);
    defer manager.deinit();
    
    // Test basic repo format
    const dep1 = try manager.fetchLatest("owner/repo");
    defer allocator.free(dep1.url);
    defer allocator.free(dep1.rev);
    defer allocator.free(dep1.name);
    
    try testing.expect(std.mem.eql(u8, dep1.name, "repo"));
    try testing.expect(std.mem.eql(u8, dep1.rev, "main"));
    try testing.expect(std.mem.startsWith(u8, dep1.url, "https://github.com/owner/repo"));
    
    // Test repo format with version
    const dep2 = try manager.fetchLatest("owner/repo@1.0.0");
    defer allocator.free(dep2.url);
    defer allocator.free(dep2.rev);
    defer allocator.free(dep2.name);
    
    try testing.expect(std.mem.eql(u8, dep2.name, "repo"));
    try testing.expect(std.mem.eql(u8, dep2.rev, "v1.0.0"));
    
    // Test json dependency special handling
    const json_dep = try manager.fetchLatest("nlohmann/json");
    defer allocator.free(json_dep.url);
    defer allocator.free(json_dep.rev);
    defer allocator.free(json_dep.name);
    defer { if (json_dep.cmake_package) |p| allocator.free(p); }
    defer { if (json_dep.include_path) |p| allocator.free(p); }

    try testing.expect(std.mem.eql(u8, json_dep.name, "json"));
    try testing.expect(std.mem.eql(u8, json_dep.cmake_package.?, "nlohmann_json"));
    try testing.expect(std.mem.eql(u8, json_dep.include_path.?, "single_include"));
}
