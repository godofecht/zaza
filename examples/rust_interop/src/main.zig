const std = @import("std");

/// Zig 0.14 spells these `std.io.getStdOut()` / `std.io.getStdErr()`; Zig 0.15
/// removed `std.io.getStd*` and made the unbuffered `File.writer` take a
/// buffer; Zig 0.16 moved `File` under `std.Io` and replaced the writer with
/// the `std.Io.Writer` interface. Only the taken branch is analysed.
const on_016 = !@hasDecl(std.fs, "File");

const StdWriter = if (on_016)
    *std.Io.Writer
else if (@hasDecl(std.fs.File, "DeprecatedWriter"))
    std.fs.File.DeprecatedWriter
else
    std.fs.File.Writer;

/// 0.16 only. The `File.Writer` has to outlive the interface pointer handed
/// back, and an empty buffer keeps writes unbuffered like the older spellings.
const std_streams = struct {
    var out: std.Io.File.Writer = undefined;
};

fn stdoutWriter() StdWriter {
    if (comptime on_016) {
        const io = std.Io.Threaded.global_single_threaded.io();
        std_streams.out = std.Io.File.stdout().writerStreaming(io, &.{});
        return &std_streams.out.interface;
    } else {
        const f = if (@hasDecl(std.fs.File, "stdout")) std.fs.File.stdout() else std.io.getStdOut();
        return if (@hasDecl(std.fs.File, "deprecatedWriter")) f.deprecatedWriter() else f.writer();
    }
}

// Import the Rust library's C-ABI functions.
const rust = @cImport({
    @cInclude("rust_math.h");
});

pub fn main() !void {
    const stdout = stdoutWriter();

    try stdout.print("=== Zaza Rust Interop Demo ===\n\n", .{});

    // rust_add
    const sum = rust.rust_add(17, 25);
    try stdout.print("rust_add(17, 25) = {}\n", .{sum});

    // rust_factorial
    const fact5 = rust.rust_factorial(5);
    const fact10 = rust.rust_factorial(10);
    try stdout.print("rust_factorial(5)  = {}\n", .{fact5});
    try stdout.print("rust_factorial(10) = {}\n", .{fact10});

    // rust_strlen
    const msg = "Hello from Zig to Rust!";
    const len = rust.rust_strlen(msg);
    try stdout.print("rust_strlen(\"{s}\") = {}\n", .{ msg, len });

    try stdout.print("\nAll Rust interop calls succeeded!\n", .{});
}
