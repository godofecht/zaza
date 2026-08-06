//! zaza-import — generate a starter Zaza build.zig from a CMake project's
//! compile_commands.json (zaza#43).
//!
//! CMake emits compile_commands.json with CMAKE_EXPORT_COMPILE_COMMANDS=ON. This
//! reads it, extracts the include directories, preprocessor defines, language
//! standard, and source files the compiler was actually invoked with, and writes
//! a Zaza target as a starting point. Unsupported CMake concepts become explicit
//! TODO comments rather than silent omissions.
//!
//!   zaza-import <compile_commands.json> [--name NAME] [--kind exe|static|shared] [--out PATH]
//!
//! Writes to --out (default build.zig.generated). Cross-lane IO/args go through
//! build_lib/compat.zig, the same adaptor the rest of zaza uses for 0.14–0.16.
//! Collections use the unmanaged variants, which are stable across those lanes.
const std = @import("std");
const compat = @import("compat");

const Kind = enum { exe, static, shared };
const StrSet = std.StringArrayHashMapUnmanaged(void);
const StrList = std.ArrayListUnmanaged([]const u8);
const Bytes = std.ArrayListUnmanaged(u8);

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

const Parsed = struct {
    sources: StrSet = .empty,
    includes: StrSet = .empty,
    defines: StrSet = .empty,
    unknown_flags: StrSet = .empty,
    cpp_std: ?[]const u8 = null,
    c_std: ?[]const u8 = null,
    saw_cpp: bool = false,
};

fn dispatch(a: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print(
            "usage: zaza-import <compile_commands.json> [--name NAME] [--kind exe|static|shared] [--out PATH]\n",
            .{},
        );
        std.process.exit(2);
    }
    var cc_path: []const u8 = args[1];
    var name: []const u8 = "imported";
    var out_path: []const u8 = "build.zig.generated";
    var kind: Kind = .exe;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--name") and i + 1 < args.len) {
            i += 1;
            name = args[i];
        } else if (std.mem.eql(u8, arg, "--out") and i + 1 < args.len) {
            i += 1;
            out_path = args[i];
        } else if (std.mem.eql(u8, arg, "--kind") and i + 1 < args.len) {
            i += 1;
            kind = std.meta.stringToEnum(Kind, args[i]) orelse .exe;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            cc_path = arg;
        }
    }

    const ioh = compat.io();
    const bytes = compat.readFile(ioh, a, cc_path) orelse {
        std.debug.print("zaza-import: cannot read {s}\n", .{cc_path});
        std.process.exit(1);
    };

    var p = Parsed{};
    const doc = std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}) catch {
        std.debug.print("zaza-import: {s} is not valid JSON\n", .{cc_path});
        std.process.exit(1);
    };
    if (doc != .array) {
        std.debug.print("zaza-import: {s} is not a compile_commands.json array\n", .{cc_path});
        std.process.exit(1);
    }
    for (doc.array.items) |entry| {
        if (entry != .object) continue;
        const obj = entry.object;
        if (obj.get("file")) |f| {
            if (f == .string) try p.sources.put(a, f.string, {});
        }
        try parseArgs(a, &p, obj);
    }

    const rendered = try render(a, p, name, kind);
    try compat.writeFile(ioh, out_path, rendered);
    std.debug.print(
        "zaza-import: wrote {s} ({d} sources, {d} include dirs, {d} defines). Review the TODOs.\n",
        .{ out_path, p.sources.count(), p.includes.count(), p.defines.count() },
    );
}

fn parseArgs(a: std.mem.Allocator, p: *Parsed, obj: std.json.ObjectMap) !void {
    var toks: StrList = .empty;
    if (obj.get("arguments")) |arr| {
        if (arr == .array) for (arr.array.items) |t| {
            if (t == .string) try toks.append(a, t.string);
        };
    } else if (obj.get("command")) |c| {
        if (c == .string) {
            var it = std.mem.tokenizeScalar(u8, c.string, ' ');
            while (it.next()) |t| try toks.append(a, t);
        }
    }
    var j: usize = 0;
    while (j < toks.items.len) : (j += 1) {
        const t = toks.items[j];
        if (std.mem.startsWith(u8, t, "-I")) {
            const v = if (t.len > 2) t[2..] else nextTok(&toks, &j) orelse continue;
            try p.includes.put(a, v, {});
        } else if (std.mem.startsWith(u8, t, "-D")) {
            const v = if (t.len > 2) t[2..] else nextTok(&toks, &j) orelse continue;
            try p.defines.put(a, v, {});
        } else if (std.mem.startsWith(u8, t, "-std=")) {
            const sv = t[5..];
            if (std.mem.indexOf(u8, sv, "++") != null) {
                p.cpp_std = stdNumber(sv);
                p.saw_cpp = true;
            } else {
                p.c_std = stdNumber(sv);
            }
        } else if (endsWithAny(t, &.{ ".cpp", ".cc", ".cxx" })) {
            p.saw_cpp = true;
        } else if (std.mem.startsWith(u8, t, "-W") or std.mem.startsWith(u8, t, "-f") or
            std.mem.startsWith(u8, t, "-O") or std.mem.startsWith(u8, t, "-g"))
        {
            try p.unknown_flags.put(a, t, {});
        }
    }
}

fn nextTok(toks: *StrList, j: *usize) ?[]const u8 {
    if (j.* + 1 < toks.items.len) {
        j.* += 1;
        return toks.items[j.*];
    }
    return null;
}

fn stdNumber(sv: []const u8) []const u8 {
    var k: usize = 0;
    while (k < sv.len and !std.ascii.isDigit(sv[k])) : (k += 1) {}
    return sv[k..];
}

fn endsWithAny(s: []const u8, suffixes: []const []const u8) bool {
    for (suffixes) |suf| if (std.mem.endsWith(u8, s, suf)) return true;
    return false;
}

fn pr(a: std.mem.Allocator, out: *Bytes, comptime fmt: []const u8, args: anytype) !void {
    try out.appendSlice(a, try std.fmt.allocPrint(a, fmt, args));
}

fn render(a: std.mem.Allocator, p: Parsed, name: []const u8, kind: Kind) ![]const u8 {
    var out: Bytes = .empty;
    try pr(a, &out,
        \\// Generated by zaza-import from compile_commands.json.
        \\// A starting point, not a finished build — review the TODOs below.
        \\const std = @import("std");
        \\const zaza = @import("zaza").api;
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\
    , .{});

    const ctor = switch (kind) {
        .exe => "executable",
        .static => "staticLibrary",
        .shared => "sharedLibrary",
    };
    try pr(a, &out, "    var t = zaza.Target.{s}(.{{\n", .{ctor});
    try pr(a, &out, "        .name = \"{s}\",\n", .{name});

    try writeList(a, &out, "source_files", p.sources.keys());
    if (p.includes.count() > 0) try writeList(a, &out, "public_include_dirs", p.includes.keys());
    if (p.defines.count() > 0) try writeList(a, &out, "public_defines", p.defines.keys());
    if (!p.saw_cpp) {
        if (p.c_std) |cs| try pr(a, &out, "        .c_std = \"{s}\",\n", .{cs});
    } else if (p.cpp_std) |cs| {
        try pr(a, &out, "        .cpp_std = \"{s}\",\n", .{cs});
    }
    try pr(a, &out,
        \\    }});
        \\    const artifact = t.buildWithTarget(b, target) catch @panic("build failed");
        \\    b.installArtifact(artifact);
        \\
    , .{});

    if (p.unknown_flags.count() > 0) {
        try pr(a, &out, "\n    // TODO(zaza-import): these compile flags were seen but not mapped;\n", .{});
        try pr(a, &out, "    //   add them as cpp_flags if they matter:\n", .{});
        for (p.unknown_flags.keys()) |f| try pr(a, &out, "    //     {s}\n", .{f});
    }
    try pr(a, &out,
        \\
        \\    // TODO(zaza-import): compile_commands.json has no target graph, so every
        \\    //   translation unit was merged into one target. Split into per-library
        \\    //   targets and wire link deps + usage requirements (public/private) by hand.
        \\    // TODO(zaza-import): system/link libraries and install rules are not in
        \\    //   compile_commands.json; add public_link_libs / install_* as needed.
        \\}}
        \\
    , .{});
    return out.items;
}

fn writeList(a: std.mem.Allocator, out: *Bytes, field: []const u8, items: []const []const u8) !void {
    try pr(a, out, "        .{s} = &.{{", .{field});
    for (items, 0..) |s, idx| {
        if (idx != 0) try pr(a, out, ",", .{});
        try pr(a, out, " \"{s}\"", .{s});
    }
    try pr(a, out, " }},\n", .{});
}
