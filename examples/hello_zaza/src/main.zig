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

pub fn main() !void {
    const stdout = stdoutWriter();
    try stdout.print("\n\x1b[1;36m=== RUN: hello_zaza_zig ===\x1b[0m\n", .{});
    try stdout.print("lang: zig\n", .{});
    try stdout.print("msg: hello_zaza (zig)\n", .{});
}
