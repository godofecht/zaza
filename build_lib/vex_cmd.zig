const std = @import("std");

pub fn addCommandStep(b: *std.Build, name: []const u8, argv: []const []const u8) *std.Build.Step {
    const run = b.addSystemCommand(argv);
    run.setName(name);
    run.stdio = .inherit;
    return &run.step;
}
