const std = @import("std");

/// Zig 0.14 spells these `std.io.getStdOut()` / `std.io.getStdErr()`; Zig 0.15
/// removed `std.io.getStd*` and made the unbuffered `File.writer` take a buffer.
const StdWriter = if (@hasDecl(std.fs.File, "DeprecatedWriter"))
    std.fs.File.DeprecatedWriter
else
    std.fs.File.Writer;

fn stdoutWriter() StdWriter {
    const f = if (@hasDecl(std.fs.File, "stdout")) std.fs.File.stdout() else std.io.getStdOut();
    return if (@hasDecl(std.fs.File, "deprecatedWriter")) f.deprecatedWriter() else f.writer();
}

pub fn main() !void {
    const stdout = stdoutWriter();
    try stdout.print("\n\x1b[1;36m=== RUN: hello_zaza_zig ===\x1b[0m\n", .{});
    try stdout.print("lang: zig\n", .{});
    try stdout.print("msg: hello_zaza (zig)\n", .{});
}
