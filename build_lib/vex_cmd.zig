const std = @import("std");
const hints = @import("interop_hints.zig");

pub const CommandStep = struct {
    step: std.Build.Step,
    argv: []const []const u8,
    b: *std.Build,

    pub fn init(b: *std.Build, name: []const u8, argv: []const []const u8) *CommandStep {
        const self = b.allocator.create(CommandStep) catch unreachable;
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = name,
                .owner = b,
                .makeFn = make,
            }),
            .argv = argv,
            .b = b,
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const self: *CommandStep = @fieldParentPtr("step", step);

        var child = std.process.Child.init(self.argv, std.heap.page_allocator);
        child.cwd = self.b.build_root.path;
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| if (code != 0) {
                if (hints.commandHint(self.argv)) |hint| {
                    std.debug.print("[vex] hint: {s}\n", .{hint});
                }
                return error.CommandFailed;
            },
            else => return error.CommandFailed,
        }
    }
};

pub fn addCommandStep(b: *std.Build, name: []const u8, argv: []const []const u8) *std.Build.Step {
    const cmd = CommandStep.init(b, name, argv);
    return &cmd.step;
}
