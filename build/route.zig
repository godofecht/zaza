const std = @import("std");

pub const Route = struct {
    const Self = @This();
    const RouteHandler = *const fn(*std.Build) anyerror!void;

    name: []const u8,
    description: []const u8,
    handler: RouteHandler,
    step: *std.Build.Step,

    pub fn create(b: *std.Build, name: []const u8, description: []const u8, handler: RouteHandler) !*Self {
        const route = try b.allocator.create(Self);
        route.* = .{
            .name = name,
            .description = description,
            .handler = handler,
            .step = b.step(name, description),
        };

        // Add a simple command to mark the step
        const cmd = b.addSystemCommand(&.{"echo", "Running step:", name});
        route.step.dependOn(&cmd.step);

        return route;
    }

    pub fn run(self: *Self, b: *std.Build) !void {
        if (b.args) |args| {
            for (args) |arg| {
                if (std.mem.eql(u8, arg, self.name)) {
                    try self.handler(b);
                    break;
                }
            }
        }
    }
}; 