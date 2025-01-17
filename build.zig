const std = @import("std");
const json_example = @import("examples/json/build.zig");
const juce_example = @import("examples/juce/build.zig");

pub fn build(b: *std.Build) !void {
    try json_example.example.build(b);
    try juce_example.example.build(b);
}
