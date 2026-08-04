const std = @import("std");

pub fn main() void {
    const arch = @import("builtin").target.cpu.arch;
    std.debug.print("universal binary demo, running as {s}\n", .{@tagName(arch)});
}
