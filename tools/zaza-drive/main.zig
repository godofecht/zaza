// zaza-drive: a native, ninja-esque build driver.
//
// The Zig build system compiles and runs build.zig on every invocation and
// content-hashes its inputs to validate the cache. That is correct and it is
// slow: a no-op costs tens of milliseconds before any real work. This driver
// skips all of it. It reads a manifest, stats the sources and their recorded
// dependencies, compiles only what is dirty, and links only when an object
// changed. A no-op is a handful of stat calls.
//
// Correctness comes from depfiles. Each object is compiled with `-MMD -MF`,
// which writes the exact set of headers that translation unit included. On the
// next run the driver reads that set and treats the object as dirty when the
// source or any recorded header is newer. A stat-only driver would miss a
// header edit; this one does not.
//
// The manifest is a small line-based format written by the caller:
//
//   compiler zig cc          # argv prefix for a compile/link invocation
//   cflags -std=c++17 -g -Iinclude
//   outdir .zaza-drive
//   bin app
//   src src/main.cpp
//   src src/unit_0.cpp
//   ...
//
// `compiler` and `cflags` may each appear once; `src` repeats. Paths are
// relative to the working directory the driver runs in.

const std = @import("std");

const Manifest = struct {
    compiler: [][]const u8,
    cflags: [][]const u8,
    outdir: []const u8,
    bin: []const u8,
    srcs: [][]const u8,
};

fn splitArgs(a: std.mem.Allocator, rest: []const u8) ![][]const u8 {
    var list = std.ArrayListUnmanaged([]const u8).empty;
    var it = std.mem.tokenizeScalar(u8, rest, ' ');
    while (it.next()) |tok| try list.append(a, try a.dupe(u8, tok));
    return list.toOwnedSlice(a);
}

fn parseManifest(a: std.mem.Allocator, text: []const u8) !Manifest {
    var compiler: [][]const u8 = &.{};
    var cflags: [][]const u8 = &.{};
    var outdir: []const u8 = ".zaza-drive";
    var bin: []const u8 = "app";
    var srcs = std.ArrayListUnmanaged([]const u8).empty;

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r\t");
        if (line.len == 0 or line[0] == '#') continue;
        const sp = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
        const key = line[0..sp];
        const rest = std.mem.trim(u8, line[@min(sp + 1, line.len)..], " \t");
        if (std.mem.eql(u8, key, "compiler")) {
            compiler = try splitArgs(a, rest);
        } else if (std.mem.eql(u8, key, "cflags")) {
            cflags = try splitArgs(a, rest);
        } else if (std.mem.eql(u8, key, "outdir")) {
            outdir = try a.dupe(u8, rest);
        } else if (std.mem.eql(u8, key, "bin")) {
            bin = try a.dupe(u8, rest);
        } else if (std.mem.eql(u8, key, "src")) {
            try srcs.append(a, try a.dupe(u8, rest));
        }
    }
    if (compiler.len == 0) return error.ManifestMissingCompiler;
    return .{
        .compiler = compiler,
        .cflags = cflags,
        .outdir = outdir,
        .bin = bin,
        .srcs = try srcs.toOwnedSlice(a),
    };
}

// The Zig 0.14 / 0.15 / 0.16 divergences live in the compat adaptor. These
// thin wrappers keep the call sites below unchanged. `io` is a real Io on 0.16
// and an ignored void on the older versions.
const compat = @import("compat");
const has_io = compat.has_io;

fn statMtime(io: anytype, path: []const u8) ?i128 {
    return compat.mtimeNs(io, path);
}

fn readFileZ(io: anytype, a: std.mem.Allocator, path: []const u8) ?[]u8 {
    return compat.readFile(io, a, path);
}

fn makeDirZ(io: anytype, path: []const u8) void {
    compat.makePath(io, path);
}

/// Spawn a child and return it. On 0.16 spawning is a std.process free function
/// taking an Io; on the older versions it is Child.init plus spawn.
fn spawnProc(io: anytype, env: anytype, a: std.mem.Allocator, argv: []const []const u8) !std.process.Child {
    return compat.spawn(io, env, a, argv);
}

fn sleepMs(io: anytype, ms: u64) void {
    compat.sleepMs(io, ms);
}

/// Wait for a child and return its exit code (non-zero for any abnormal exit).
fn waitProc(io: anytype, ch: *std.process.Child) !u8 {
    return compat.wait(io, ch);
}

// A .d file is Make syntax: "target: dep1 dep2 \<newline> dep3 ...". Return the
// newest mtime across every listed prerequisite, or null if none are readable.
fn newestDep(io: anytype, a: std.mem.Allocator, depfile: []const u8) ?i128 {
    const text = readFileZ(io, a, depfile) orelse return null;
    defer a.free(text);
    const colon = std.mem.indexOfScalar(u8, text, ':') orelse return null;
    var newest: ?i128 = null;
    var it = std.mem.tokenizeAny(u8, text[colon + 1 ..], " \t\r\n\\");
    while (it.next()) |dep| {
        if (dep.len == 0) continue;
        if (statMtime(io, dep)) |m| {
            if (newest == null or m > newest.?) newest = m;
        }
    }
    return newest;
}

const Unit = struct {
    src: []const u8,
    obj: []const u8,
    dep: []const u8,
    dirty: bool,
};

fn objName(a: std.mem.Allocator, outdir: []const u8, src: []const u8) ![]const u8 {
    // Flatten the path so src/a/b.cpp and src/c/b.cpp do not collide.
    const rel = try a.dupe(u8, src);
    for (rel) |*c| {
        if (c.* == '/' or c.* == '\\') c.* = '_';
    }
    return std.fmt.allocPrint(a, "{s}/{s}.o", .{ outdir, rel });
}

// Zig 0.16 removed std.process.argsAlloc and hands args to main through an
// Init parameter, a signature 0.14 and 0.15 do not accept. main cannot have one
// shape across all three, so it is comptime-dispatched to a version-specific
// entry. Only the selected function is analysed, so the other's use of a
// removed API never compiles.
pub const main = if (@import("builtin").zig_version.minor >= 16) main016 else mainPre016;

fn mainPre016() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const args = try std.process.argsAlloc(a);
    var watch = false;
    var manifest: ?[]const u8 = null;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--watch")) watch = true else manifest = arg;
    }
    // Older Child.init inherits the parent environment, so nothing to pass.
    return run(a, {}, manifest orelse return usageExit(), watch);
}

fn main016(init: std.process.Init.Minimal) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    var it = init.args.iterate();
    _ = it.next(); // argv[0]
    var watch = false;
    var manifest: ?[]const u8 = null;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--watch")) watch = true else manifest = arg;
    }
    // 0.16 spawns with an empty environment unless one is passed, so hand the
    // parent environment down for the child compilers to inherit.
    return run(a, init.environ, manifest orelse return usageExit(), watch);
}

fn usageExit() noreturn {
    std.debug.print("usage: zaza-drive [--watch] <manifest>\n", .{});
    std.process.exit(2);
}

fn run(a: std.mem.Allocator, environ: anytype, manifest_path: []const u8, watch: bool) !void {
    // On 0.16 every filesystem and process call needs an Io handle, and spawns
    // need an explicit environment map. On the older versions both are ignored
    // voids and Child.init inherits the environment.
    var threaded = if (comptime has_io) std.Io.Threaded.init(a, .{}) else {};
    const io = if (comptime has_io) threaded.io() else {};
    defer if (comptime has_io) threaded.deinit();

    var env_map = if (comptime has_io) try environ.createMap(a) else {};
    defer if (comptime has_io) env_map.deinit();
    const env = if (comptime has_io) &env_map else {};

    const text = readFileZ(io, a, manifest_path) orelse return error.MissingManifest;
    const m = try parseManifest(a, text);

    if (!watch) {
        const r = try buildOnce(a, io, env, m);
        if (r == .failed) std.process.exit(1);
        return;
    }

    // Watch mode: poll the sources and rebuild whatever is dirty. The build's
    // own dirty check makes an unchanged poll a handful of stat calls, so a
    // 200ms interval costs almost nothing while idle. A rebuild is not faster
    // than a one-shot build; watch mode removes the command, not the work.
    std.debug.print("zaza-drive: watching {d} sources; edit and save to rebuild, ctrl-c to stop\n", .{m.srcs.len});
    while (true) {
        const r = buildOnce(a, io, env, m) catch |e| {
            std.debug.print("zaza-drive: {s}\n", .{@errorName(e)});
            sleepMs(io, 200);
            continue;
        };
        switch (r) {
            .rebuilt => std.debug.print("zaza-drive: rebuilt\n", .{}),
            .failed => std.debug.print("zaza-drive: build failed\n", .{}),
            .up_to_date => {},
        }
        sleepMs(io, 200);
    }
}

const BuildOutcome = enum { up_to_date, rebuilt, failed };

// One build pass: detect dirty units, compile them, link if anything changed.
// Uses a scratch arena so a long-running watch loop does not accumulate memory.
fn buildOnce(gpa: std.mem.Allocator, io: anytype, env: anytype, m: Manifest) !BuildOutcome {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    makeDirZ(io, m.outdir);

    var units = try a.alloc(Unit, m.srcs.len);
    var any_dirty = false;
    for (m.srcs, 0..) |src, i| {
        const obj = try objName(a, m.outdir, src);
        const dep = try std.fmt.allocPrint(a, "{s}.d", .{obj});
        const obj_m = statMtime(io, obj);
        var dirty = false;
        if (obj_m == null) {
            dirty = true;
        } else {
            const src_m = statMtime(io, src) orelse return error.MissingSource;
            if (src_m > obj_m.?) {
                dirty = true;
            } else if (newestDep(io, a, dep)) |dm| {
                if (dm > obj_m.?) dirty = true;
            }
        }
        units[i] = .{ .src = src, .obj = obj, .dep = dep, .dirty = dirty };
        if (dirty) any_dirty = true;
    }

    // Compile dirty units in parallel. Each records its own depfile.
    var procs = std.ArrayListUnmanaged(std.process.Child).empty;
    for (units) |u| {
        if (!u.dirty) continue;
        var argv = std.ArrayListUnmanaged([]const u8).empty;
        try argv.appendSlice(a, m.compiler);
        try argv.appendSlice(a, m.cflags);
        try argv.appendSlice(a, &.{ "-MMD", "-MF", u.dep, "-c", u.src, "-o", u.obj });
        const ch = try spawnProc(io, env, a, try argv.toOwnedSlice(a));
        try procs.append(a, ch);
    }
    var compile_failed = false;
    for (procs.items) |*ch| {
        const code = try waitProc(io, ch);
        if (code != 0) compile_failed = true;
    }
    if (compile_failed) return .failed;

    // Link only when an object changed or the binary is missing.
    const need_link = any_dirty or statMtime(io, m.bin) == null;
    if (!need_link) return .up_to_date;

    var argv = std.ArrayListUnmanaged([]const u8).empty;
    try argv.appendSlice(a, m.compiler);
    try argv.appendSlice(a, m.cflags);
    for (units) |u| try argv.append(a, u.obj);
    try argv.appendSlice(a, &.{ "-o", m.bin });
    var ch = try spawnProc(io, env, a, try argv.toOwnedSlice(a));
    const code = try waitProc(io, &ch);
    if (code != 0) return .failed;
    return .rebuilt;
}
