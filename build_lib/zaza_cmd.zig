const std = @import("std");
const compat = @import("compat.zig");

pub fn addCommandStep(b: *std.Build, name: []const u8, argv: []const []const u8) *std.Build.Step {
    const run = b.addSystemCommand(argv);
    run.setName(name);
    run.stdio = .inherit;
    return &run.step;
}

/// An environment variable, or null if unset. Caller frees the result. The
/// cross-version handling lives in the compat adaptor.
pub fn envString(b: *std.Build, name: []const u8) ?[]const u8 {
    return compat.buildEnv(b, name);
}
