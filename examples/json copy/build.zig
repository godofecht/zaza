const std = @import("std");
const builtin = @import("builtin");
const cpp = @import("build_lib/cpp_example.zig");
const viewer = @import("build_lib/build_viewer.zig");

pub const example = cpp.CppExample{
    .name = "json_example",
    .description = "JSON example using nlohmann/json",
    .source_files = &.{"src/main.cpp"},
    .include_dirs = &.{"deps/json/single_include"},
    .cpp_flags = &.{cpp.Defines.exceptions},
    .deps = &.{cpp.Deps.nlohmann_json},
    .configs = &.{cpp.Configs.Release},
    .deps_build_system = .Zig,    // Use Zig since json is header-only
    .main_build_system = .Zig,    // Use Zig for main project
    .cpp_std = "17",  // Set C++ standard directly
};

pub fn build(b: *std.Build) !void {
    const exe = try example.build(b);

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_cmd.step);

    // Add optional CMake generation step
    const cmake_step = b.step("cmake", "Generate CMakeLists.txt for CMake compatibility");
    const gen = b.addSystemCommand(&.{"true"});  // Dummy command that always succeeds
    try example.generateCMake(b);  // Generate CMakeLists.txt
    cmake_step.dependOn(&gen.step);

    // Add view step to show build configuration
    const view_step = b.step("view", "View build configuration");
    
    // Create a file to store the HTML
    const cache_path = b.cache_root.path orelse ".";
    const html_path = try std.fs.path.join(b.allocator, &.{cache_path, "build_config.html"});
    
    // Write the HTML content
    const html_file = try std.fs.createFileAbsolute(html_path, .{});
    defer html_file.close();
    try viewer.viewBuildConfig(example, html_file.writer());
    
    // Create command to open the HTML file in default browser
    const open_cmd = if (builtin.target.os.tag == .windows) 
        &.{"cmd", "/C", "start", html_path} 
    else if (builtin.target.os.tag == .macos) 
        &.{"open", html_path}
    else 
        &.{"xdg-open", html_path};
        
    const view_cmd = b.addSystemCommand(open_cmd);
    view_step.dependOn(&view_cmd.step);
}
