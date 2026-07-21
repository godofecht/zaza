const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");

pub const app_config = cpp.JUCEApplication.JuceConfig{
    .name = "ZazaJuce",
    .description = "JUCE audio synth example built with Zaza",
    .version = "1.0.0",
    .company = "Zaza",
    .build_mode = .Debug,
    .cmake_root = "examples/zaza-juce",
    .juce_git_tag = "8.0.14",
    .sources = &.{"src/main.cpp"},
    .modules = &.{
        "juce_core",
        "juce_data_structures",
        "juce_events",
        "juce_graphics",
        "juce_gui_basics",
        "juce_audio_basics",
        "juce_audio_devices",
        "juce_audio_formats",
        "juce_audio_processors",
        "juce_audio_utils",
    },
};

const ZazaJuce = cpp.JUCEApplication.template(app_config);

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
