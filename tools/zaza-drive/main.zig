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
    var list = std.ArrayListUnmanaged([]const u8){};
    var it = std.mem.tokenizeScalar(u8, rest, ' ');
    while (it.next()) |tok| try list.append(a, try a.dupe(u8, tok));
    return list.toOwnedSlice(a);
}

fn parseManifest(a: std.mem.Allocator, text: []const u8) !Manifest {
    var compiler: [][]const u8 = &.{};
    var cflags: [][]const u8 = &.{};
    var outdir: []const u8 = ".zaza-drive";
    var bin: []const u8 = "app";
    var srcs = std.ArrayListUnmanaged([]const u8){};

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

fn mtimeOf(path: []const u8) ?i128 {
    const st = std.fs.cwd().statFile(path) catch return null;
    return st.mtime;
}

// A .d file is Make syntax: "target: dep1 dep2 \<newline> dep3 ...". Return the
// newest mtime across every listed prerequisite, or null if none are readable.
fn newestDep(a: std.mem.Allocator, depfile: []const u8) ?i128 {
    const text = std.fs.cwd().readFileAlloc(a, depfile, 8 * 1024 * 1024) catch return null;
    defer a.free(text);
    const colon = std.mem.indexOfScalar(u8, text, ':') orelse return null;
    var newest: ?i128 = null;
    var it = std.mem.tokenizeAny(u8, text[colon + 1 ..], " \t\r\n\\");
    while (it.next()) |dep| {
        if (dep.len == 0) continue;
        if (mtimeOf(dep)) |m| {
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

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const args = try std.process.argsAlloc(a);
    if (args.len < 2) {
        std.debug.print("usage: zaza-drive <manifest>\n", .{});
        std.process.exit(2);
    }
    const text = try std.fs.cwd().readFileAlloc(a, args[1], 8 * 1024 * 1024);
    const m = try parseManifest(a, text);

    std.fs.cwd().makePath(m.outdir) catch {};

    // Decide dirtiness for each unit.
    var units = try a.alloc(Unit, m.srcs.len);
    var any_dirty = false;
    for (m.srcs, 0..) |src, i| {
        const obj = try objName(a, m.outdir, src);
        const dep = try std.fmt.allocPrint(a, "{s}.d", .{obj});
        const obj_m = mtimeOf(obj);
        var dirty = false;
        if (obj_m == null) {
            dirty = true;
        } else {
            const src_m = mtimeOf(src) orelse return error.MissingSource;
            if (src_m > obj_m.?) {
                dirty = true;
            } else if (newestDep(a, dep)) |dm| {
                if (dm > obj_m.?) dirty = true;
            }
        }
        units[i] = .{ .src = src, .obj = obj, .dep = dep, .dirty = dirty };
        if (dirty) any_dirty = true;
    }

    // Compile dirty units in parallel. Each records its own depfile.
    var procs = std.ArrayListUnmanaged(std.process.Child){};
    for (units) |u| {
        if (!u.dirty) continue;
        var argv = std.ArrayListUnmanaged([]const u8){};
        try argv.appendSlice(a, m.compiler);
        try argv.appendSlice(a, m.cflags);
        try argv.appendSlice(a, &.{ "-MMD", "-MF", u.dep, "-c", u.src, "-o", u.obj });
        var ch = std.process.Child.init(try argv.toOwnedSlice(a), a);
        try ch.spawn();
        try procs.append(a, ch);
    }
    var compile_failed = false;
    for (procs.items) |*ch| {
        const term = try ch.wait();
        switch (term) {
            .Exited => |code| if (code != 0) {
                compile_failed = true;
            },
            else => compile_failed = true,
        }
    }
    if (compile_failed) {
        std.debug.print("zaza-drive: a compile step failed\n", .{});
        std.process.exit(1);
    }

    // Link only when an object changed or the binary is missing.
    const need_link = any_dirty or mtimeOf(m.bin) == null;
    if (need_link) {
        var argv = std.ArrayListUnmanaged([]const u8){};
        try argv.appendSlice(a, m.compiler);
        try argv.appendSlice(a, m.cflags);
        for (units) |u| try argv.append(a, u.obj);
        try argv.appendSlice(a, &.{ "-o", m.bin });
        var ch = std.process.Child.init(try argv.toOwnedSlice(a), a);
        const term = try ch.spawnAndWait();
        switch (term) {
            .Exited => |code| if (code != 0) std.process.exit(1),
            else => std.process.exit(1),
        }
    }
}
