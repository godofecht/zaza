const std = @import("std");
const Calculator = @import("calculator.zig").Calculator;

pub fn main() !void {
    var calc = try Calculator.create();
    defer calc.destroy();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("10 + 5 = {d}\n", .{calc.add(10, 5)});
    try stdout.print("10 - 5 = {d}\n", .{calc.subtract(10, 5)});
    try stdout.print("10 * 5 = {d}\n", .{calc.multiply(10, 5)});
    try stdout.print("10 / 3 = {d:.2}\n", .{calc.divide(10, 3)});
} 