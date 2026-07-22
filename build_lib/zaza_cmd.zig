const std = @import("std");

pub fn addCommandStep(b: *std.Build, name: []const u8, argv: []const []const u8) *std.Build.Step {
    const run = b.addSystemCommand(argv);
    run.setName(name);
    run.stdio = .inherit;
    return &run.step;
}

/// Zig 0.16 removed std.process.getEnvVarOwned and keeps the environment on
/// the build graph, under a field whose name also changed. Callers free what
/// this returns, so both branches hand back owned memory. Only the taken
/// branch is analysed.
pub fn envString(b: *std.Build, name: []const u8) ?[]const u8 {
    if (comptime @hasDecl(std.process, "getEnvVarOwned")) {
        return std.process.getEnvVarOwned(b.allocator, name) catch null;
    } else {
        const borrowed = b.graph.environ_map.get(name) orelse return null;
        return b.allocator.dupe(u8, borrowed) catch null;
    }
}
