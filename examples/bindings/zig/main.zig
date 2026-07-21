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
const Calculator = @import("calculator.zig").Calculator;

pub fn main() !void {
    var calc = try Calculator.create();
    defer calc.destroy();

    const stdout = stdoutWriter();

    try stdout.print("10 + 5 = {d}\n", .{calc.add(10, 5)});
    try stdout.print("10 - 5 = {d}\n", .{calc.subtract(10, 5)});
    try stdout.print("10 * 5 = {d}\n", .{calc.multiply(10, 5)});
    try stdout.print("10 / 3 = {d:.2}\n", .{calc.divide(10, 3)});
} 