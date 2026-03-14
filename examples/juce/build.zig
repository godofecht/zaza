const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

const app_config = cpp.JUCEApplication.JuceConfig{
    .name = "JuceExample",
    .description = "JUCE example using FetchContent",
    .version = "1.0.0",
    .company = "Example",
    .build_mode = .Debug,
    .cmake_root = "examples/juce",
    .juce_git_tag = "7.0.9",
    .sources = &.{"src/main.cpp"},
    .modules = &.{
        "juce_core",
        "juce_data_structures", 
        "juce_events",
        "juce_graphics",
        "juce_gui_basics",
    },
};

const JuceExample = cpp.JUCEApplication.template(app_config);

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    try buildWithTarget(b, target);
}

pub fn buildWithTarget(b: *std.Build, target: std.Build.ResolvedTarget) !void {
    var app = cpp.JUCEApplication.builder(b);
    defer app.deinit();

    const app_builder = try app.configure(app_config);
    const example = try app_builder.build(.{ .enable_system_commands = true });
    _ = example.buildWithTarget(b, target) catch |err| switch (err) {
        error.NoExecutableBuilt => return,
        else => return err,
    };
}
