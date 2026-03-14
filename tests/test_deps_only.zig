const std = @import("std");
const testing = std.testing;
const deps = @import("dependencies");

test "DependencyManager initialization" {
    var manager = deps.DependencyManager.init(testing.allocator);
    defer manager.deinit();
    
    try testing.expect(manager.dependencies.items.len == 0);
    try testing.expect(manager.cmake_paths.items.len == 0);
    try testing.expect(std.mem.eql(u8, manager.deps_dir, "deps"));
    try testing.expect(std.mem.eql(u8, manager.workspace_root, "."));
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
}

test "fetchLatest" {
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
    try testing.expect(std.mem.startsWith(u8, dep1.url, "https://github.com/owner/repo"));
    
    // Test repo format with version
    const dep2 = try manager.fetchLatest("owner/repo@1.0.0");
    defer testing.allocator.free(dep2.url);
    defer testing.allocator.free(dep2.rev);
    defer testing.allocator.free(dep2.name);
    if (dep2.cmake_package) |pkg| testing.allocator.free(pkg);
    if (dep2.include_path) |path| testing.allocator.free(path);
    
    try testing.expect(std.mem.eql(u8, dep2.name, "repo"));
    try testing.expect(std.mem.eql(u8, dep2.rev, "v1.0.0"));
    
    // Test json dependency special handling
    const json_dep = try manager.fetchLatest("nlohmann/json");
    defer testing.allocator.free(json_dep.url);
    defer testing.allocator.free(json_dep.rev);
    defer testing.allocator.free(json_dep.name);
    defer { if (json_dep.cmake_package) |pkg| testing.allocator.free(pkg); }
    defer { if (json_dep.include_path) |path| testing.allocator.free(path); }

    try testing.expect(std.mem.eql(u8, json_dep.name, "json"));
    try testing.expect(std.mem.eql(u8, json_dep.cmake_package.?, "nlohmann_json"));
    try testing.expect(std.mem.eql(u8, json_dep.include_path.?, "single_include"));
}
