const std = @import("std");
const testing = std.testing;

// Import all modules from root
const builder = @import("../builder.zig");
const deps = @import("../dependencies.zig");
const zigcpp = @import("../zigcpp.zig");

test "Platform definitions" {
    try testing.expect(builder.Platform.linux_x64.arch == .x86_64);
    try testing.expect(builder.Platform.linux_x64.os == .linux);
    try testing.expect(std.mem.eql(u8, builder.Platform.linux_x64.name, "linux-x64"));
    
    try testing.expect(builder.Platform.windows_x64.arch == .x86_64);
    try testing.expect(builder.Platform.windows_x64.os == .windows);
    try testing.expect(std.mem.eql(u8, builder.Platform.windows_x64.name, "windows-x64"));
    
    try testing.expect(builder.Platform.macos_arm64.arch == .aarch64);
    try testing.expect(builder.Platform.macos_arm64.os == .macos);
    try testing.expect(std.mem.eql(u8, builder.Platform.macos_arm64.name, "macos-arm64"));
    
    try testing.expect(builder.Platform.wasm.arch == .wasm32);
    try testing.expect(builder.Platform.wasm.os == .wasi);
    try testing.expect(std.mem.eql(u8, builder.Platform.wasm.name, "wasm"));
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
    
    // Check that desktop platforms are indeed desktop platforms
    for (builder.Platform.desktop) |platform| {
        try testing.expect(platform.os == .linux or platform.os == .windows or platform.os == .macos);
    }
}

test "DependencyManager initialization" {
    var manager = deps.DependencyManager.init(testing.allocator);
    defer manager.deinit();
    
    try testing.expect(manager.allocator == testing.allocator);
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
    try testing.expect(std.mem.eql(u8, dep.cmake_package.?, "TestPackage"));
    try testing.expect(std.mem.eql(u8, dep.subdirectory.?, "src"));
    try testing.expect(std.mem.eql(u8, dep.include_path.?, "include"));
}

test "fetchLatest" {
    var manager = deps.DependencyManager.init(testing.allocator);
    defer manager.deinit();
    
    // Test basic repo format
    const dep1 = try manager.fetchLatest("owner/repo");
    defer testing.allocator.free(dep1.url);
    defer testing.allocator.free(dep1.rev);
    
    try testing.expect(std.mem.eql(u8, dep1.name, "repo"));
    try testing.expect(std.mem.eql(u8, dep1.rev, "main"));
    try testing.expect(std.mem.startsWith(u8, dep1.url, "https://github.com/owner/repo"));
    
    // Test repo format with version
    const dep2 = try manager.fetchLatest("owner/repo@1.0.0");
    defer testing.allocator.free(dep2.url);
    defer testing.allocator.free(dep2.rev);
    
    try testing.expect(std.mem.eql(u8, dep2.name, "repo"));
    try testing.expect(std.mem.eql(u8, dep2.rev, "v1.0.0"));
    
    // Test json dependency special handling
    const json_dep = try manager.fetchLatest("nlohmann/json");
    defer testing.allocator.free(json_dep.url);
    defer testing.allocator.free(json_dep.rev);
    
    try testing.expect(std.mem.eql(u8, json_dep.name, "json"));
    try testing.expect(std.mem.eql(u8, json_dep.cmake_package.?, "nlohmann_json"));
    try testing.expect(std.mem.eql(u8, json_dep.include_path.?, "single_include"));
}

test "Example struct" {
    const example = builder.Example{
        .name = "test",
        .description = "test description",
        .source_files = &.{"main.cpp"},
        .platforms = &.{builder.Platform.macos_x64},
        .dependencies = &.{},
        .cpp_standard = "20",
        .defines = &.{"TEST=1"},
        .include_paths = &.{"include"},
    };
    
    try testing.expect(std.mem.eql(u8, example.name, "test"));
    try testing.expect(std.mem.eql(u8, example.description, "test description"));
    try testing.expect(example.source_files.len == 1);
    try testing.expect(example.platforms.len == 1);
    try testing.expect(example.dependencies.len == 0);
    try testing.expect(std.mem.eql(u8, example.cpp_standard, "20"));
    try testing.expect(example.defines.len == 1);
    try testing.expect(example.include_paths.len == 1);
}
