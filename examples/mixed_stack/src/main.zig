const std = @import("std");

extern fn mixed_bridge_compute(value: c_int) c_int;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("mixed stack result: {}\n", .{mixed_bridge_compute(7)});
}
