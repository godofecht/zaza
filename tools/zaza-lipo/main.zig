// zaza-lipo: a portable replacement for the parts of Apple's `lipo` that a
// build needs. It creates, inspects, and thins macOS universal (fat) binaries
// using build_lib/fatbinary.zig, so combining per-arch Mach-O slices works on
// any host, including a Linux CI runner that has no `lipo` and no Xcode.
//
//   zaza-lipo create -arch x86_64 hi_x86 -arch arm64 hi_arm -output hi
//   zaza-lipo info hi
//   zaza-lipo thin hi arm64 -output hi_arm
//
// See zaza#38. The fat-binary format is the same one `lipo -create` writes, so
// the output is interchangeable with the system tool.

const std = @import("std");
const fatbinary = @import("fatbinary");
const compat = @import("compat");

fn archFromName(name: []const u8) ?fatbinary.Arch {
    if (std.mem.eql(u8, name, "x86_64")) return .x86_64;
    if (std.mem.eql(u8, name, "arm64")) return .aarch64;
    if (std.mem.eql(u8, name, "aarch64")) return .aarch64;
    return null;
}

// Report an arch the way `lipo` names it.
fn archName(a: fatbinary.Arch) []const u8 {
    return switch (a) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
    };
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("zaza-lipo: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn usage() noreturn {
    std.debug.print(
        \\usage:
        \\  zaza-lipo create -arch <name> <file> [-arch <name> <file> ...] -output <out>
        \\  zaza-lipo info <file>
        \\  zaza-lipo thin <file> <arch> -output <out>
        \\
        \\arch names: x86_64, arm64 (aarch64 accepted)
        \\
    , .{});
    std.process.exit(2);
}

// Zig 0.16 removed std.process.argsAlloc; argv now arrives through the entry
// point's parameter, which older versions do not accept. Select the entry
// point at comptime so one dispatch body serves all three lanes, the same way
// scripts/zaza.zig does. compat.has_io is the 0.16 marker.
const on_016 = compat.has_io;

pub const main = if (on_016) main016 else mainLegacy;

fn mainLegacy() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try std.process.argsAlloc(a);
    try dispatch(a, args);
}

fn main016(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try init.args.toSlice(a);
    try dispatch(a, args);
}

fn dispatch(a: std.mem.Allocator, args: []const [:0]const u8) !void {
    const ioh = compat.io();
    if (args.len < 2) usage();
    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "create")) {
        try create(a, ioh, args[2..]);
    } else if (std.mem.eql(u8, cmd, "info")) {
        try info(a, ioh, args[2..]);
    } else if (std.mem.eql(u8, cmd, "thin")) {
        try thin(a, ioh, args[2..]);
    } else {
        std.debug.print("zaza-lipo: unknown command '{s}'\n", .{cmd});
        usage();
    }
}

fn create(a: std.mem.Allocator, ioh: anytype, args: []const [:0]const u8) !void {
    // At most one slice per two args, so this upper bound never overflows.
    const slices = try a.alloc(fatbinary.Slice, args.len);
    var n: usize = 0;
    var output: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-arch")) {
            if (i + 2 >= args.len) fail("-arch needs a <name> and a <file>", .{});
            const arch = archFromName(args[i + 1]) orelse
                fail("unknown arch '{s}'", .{args[i + 1]});
            const path = args[i + 2];
            const bytes = compat.readFile(ioh, a, path) orelse
                fail("cannot read {s}", .{path});
            slices[n] = .{ .arch = arch, .bytes = bytes };
            n += 1;
            i += 2;
        } else if (std.mem.eql(u8, arg, "-output")) {
            if (i + 1 >= args.len) fail("-output needs a path", .{});
            output = args[i + 1];
            i += 1;
        } else {
            fail("unexpected argument '{s}'", .{arg});
        }
    }

    if (n == 0) fail("no -arch slices given", .{});
    const out = output orelse fail("no -output given", .{});

    const fat = fatbinary.build(a, slices[0..n]) catch |e| switch (e) {
        error.NoSlices => fail("no slices to combine", .{}),
        error.DuplicateArch => fail("two slices share an arch", .{}),
        error.OutOfMemory => return e,
    };
    compat.writeFile(ioh, out, fat) catch |e|
        fail("cannot write {s}: {s}", .{ out, @errorName(e) });

    std.debug.print(
        "zaza-lipo: wrote {s} ({d} archs, {d} bytes)\n",
        .{ out, n, fat.len },
    );
}

fn info(a: std.mem.Allocator, ioh: anytype, args: []const [:0]const u8) !void {
    if (args.len < 1) fail("usage: zaza-lipo info <file>", .{});
    const path = args[0];
    const bytes = compat.readFile(ioh, a, path) orelse fail("cannot read {s}", .{path});

    var parsed = fatbinary.parse(a, bytes) catch |e| switch (e) {
        error.BadMagic, error.TooShort => {
            std.debug.print("Non-fat file: {s}\n", .{path});
            return;
        },
        error.TruncatedTable, error.SliceOutOfRange => fail("{s} is a malformed fat file", .{path}),
        error.OutOfMemory => return e,
    };
    defer parsed.deinit();

    std.debug.print("Architectures in the fat file: {s} are:", .{path});
    for (parsed.slices) |s| {
        const label = if (s.arch) |arch| archName(arch) else "unknown";
        std.debug.print(" {s}", .{label});
    }
    std.debug.print("\n", .{});
}

fn thin(a: std.mem.Allocator, ioh: anytype, args: []const [:0]const u8) !void {
    if (args.len < 2) fail("usage: zaza-lipo thin <file> <arch> -output <out>", .{});
    const path = args[0];
    const want = archFromName(args[1]) orelse fail("unknown arch '{s}'", .{args[1]});

    var output: ?[]const u8 = null;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-output")) {
            if (i + 1 >= args.len) fail("-output needs a path", .{});
            output = args[i + 1];
            i += 1;
        } else {
            fail("unexpected argument '{s}'", .{args[i]});
        }
    }
    const out = output orelse fail("no -output given", .{});

    const bytes = compat.readFile(ioh, a, path) orelse fail("cannot read {s}", .{path});
    var parsed = fatbinary.parse(a, bytes) catch |e|
        fail("cannot parse {s}: {s}", .{ path, @errorName(e) });
    defer parsed.deinit();

    for (parsed.slices) |s| {
        if (s.arch != null and s.arch.? == want) {
            compat.writeFile(ioh, out, s.bytes) catch |e|
                fail("cannot write {s}: {s}", .{ out, @errorName(e) });
            std.debug.print(
                "zaza-lipo: wrote {s} ({s}, {d} bytes)\n",
                .{ out, archName(want), s.bytes.len },
            );
            return;
        }
    }
    fail("arch {s} is not present in {s}", .{ args[1], path });
}
