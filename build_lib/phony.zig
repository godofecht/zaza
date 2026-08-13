//! A first-class phony orchestration target: the `add_custom_target` equivalent.
//!
//! A phony target produces no artifact. It names a group of work so `zig build
//! <name>` runs it: other targets to build first, and commands to run in order.
//! Use it to aggregate targets under one name, or to run a packaging or codegen
//! step as a named target.
//!
//! ```zig
//! const bundle = zaza.addPhonyTarget(b, .{
//!     .name = "bundle",
//!     .description = "build the app and stage its assets",
//!     .depends_on = &.{ &app.step, &tool.step },
//!     .commands = &.{
//!         &.{ "sh", "scripts/stage-assets.sh" },
//!     },
//! });
//! _ = bundle;
//! ```

const std = @import("std");

/// How to build a phony target.
pub const PhonyOptions = struct {
    /// The step name: `zig build <name>` runs it.
    name: []const u8,
    /// Shown in `zig build --list-steps`.
    description: []const u8 = "",
    /// Commands to run when the target is built, each an argv. They run in the
    /// given order.
    commands: []const []const []const u8 = &.{},
    /// Steps this target aggregates. Building the target builds these first.
    depends_on: []const *std.Build.Step = &.{},
};

/// A built phony target. `step` is the aggregate; depend other work on it, or
/// add more with `dependOn`.
pub const PhonyTarget = struct {
    step: *std.Build.Step,

    /// Make this target also build `other` first.
    pub fn dependOn(self: PhonyTarget, other: *std.Build.Step) void {
        self.step.dependOn(other);
    }
};

/// Create a phony orchestration target. Commands run in order (each waits for
/// the previous), then the target depends on every `depends_on` step, so
/// building it runs the whole group.
pub fn addPhonyTarget(b: *std.Build, opts: PhonyOptions) PhonyTarget {
    const step = b.step(opts.name, opts.description);

    var last: ?*std.Build.Step = null;
    for (opts.commands) |argv| {
        const run = b.addSystemCommand(argv);
        run.setName(b.fmt("{s}: {s}", .{ opts.name, if (argv.len > 0) argv[0] else "command" }));
        run.stdio = .inherit;
        // Chain the commands so they run in declaration order rather than in
        // whatever order the graph happens to schedule them.
        if (last) |prev| run.step.dependOn(prev);
        last = &run.step;
    }
    if (last) |l| step.dependOn(l);

    for (opts.depends_on) |dep| step.dependOn(dep);

    return .{ .step = step };
}
