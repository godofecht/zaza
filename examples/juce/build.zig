const std = @import("std");
const cpp = @import("build_lib/cpp_example.zig");

const app = cpp.JUCEApplication.Config{
    .name = "JuceExample",
    .description = "JUCE example using FetchContent",
    .version = "1.0.0",
    .company = "Example",
    .build_mode = .Debug,
    .sources = &.{"src/main.cpp"},
    .modules = &.{
        "juce_core",
        "juce_data_structures", 
        "juce_events",
        "juce_graphics",
        "juce_gui_basics",
    },
};

const JuceExample = cpp.JUCEApplication.template(app);

pub fn build(b: *std.Build) !void {
    try JuceExample.build(b);
} 