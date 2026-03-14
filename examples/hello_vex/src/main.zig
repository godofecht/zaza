const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n\x1b[1;36m=== RUN: hello_vex_zig ===\x1b[0m\n", .{});
    try stdout.print("lang: zig\n", .{});
    try stdout.print("msg: hello_vex (zig)\n", .{});
}
