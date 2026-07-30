//! One place for the Zig 0.14 / 0.15 / 0.16 divergences.
//!
//! Zig 0.16 moved the filesystem and process APIs under `std.Io` and threads an
//! `Io` handle through every call. It also removed `std.process.getEnvVarOwned`,
//! renamed process `Term` tags to lowercase, and replaced the file writer with
//! the `std.Io.Writer` interface. The rest of the codebase calls the helpers
//! here instead of branching on the version inline.
//!
//! Every helper is written so only the branch for the running compiler is
//! analysed (the condition is comptime), so a single source file compiles on
//! all three versions.

const std = @import("std");

/// True only on Zig 0.16, where filesystem and process calls take an `Io`.
pub const has_io = !@hasDecl(std.fs, "cwd");

/// A process-wide `Io` for standalone programs (tools, tests). Build steps have
/// their own handle at `b.graph.io` and should pass that instead. On 0.14 and
/// 0.15 this is a `void` the fs/process helpers ignore.
pub fn io() if (has_io) std.Io else void {
    if (comptime has_io) return std.Io.Threaded.global_single_threaded.io();
    return {};
}

// ----------------------------------------------------------------- filesystem
//
// Each helper takes an `io` value: a real `Io` on 0.16, and an ignored `void`
// on the older versions. Pass `compat.io()` from a standalone program, or
// `b.graph.io` from a build step.

/// Read a whole file, relative to the current directory. Returns null on error.
pub fn readFile(ioh: anytype, alloc: std.mem.Allocator, path: []const u8) ?[]u8 {
    if (comptime has_io) {
        return std.Io.Dir.cwd().readFileAlloc(ioh, path, alloc, .unlimited) catch null;
    } else {
        return std.fs.cwd().readFileAlloc(alloc, path, 64 * 1024 * 1024) catch null;
    }
}

/// Write a file, relative to the current directory, creating or truncating it.
pub fn writeFile(ioh: anytype, path: []const u8, data: []const u8) !void {
    if (comptime has_io) {
        try std.Io.Dir.cwd().writeFile(ioh, .{ .sub_path = path, .data = data });
    } else {
        try std.fs.cwd().writeFile(.{ .sub_path = path, .data = data });
    }
}

/// Create a directory and any missing parents. Best effort: never fails.
pub fn makePath(ioh: anytype, path: []const u8) void {
    if (comptime has_io) {
        _ = std.Io.Dir.cwd().createDirPathOpen(ioh, path, .{}) catch {};
    } else {
        std.fs.cwd().makePath(path) catch {};
    }
}

/// Whether a path exists and is accessible.
pub fn exists(ioh: anytype, path: []const u8) bool {
    if (comptime has_io) {
        std.Io.Dir.cwd().access(ioh, path, .{}) catch return false;
    } else {
        std.fs.cwd().access(path, .{}) catch return false;
    }
    return true;
}

/// Modification time in nanoseconds, or null if the file is unreadable. 0.16
/// reports it as an `Io.Timestamp`; the older versions as a plain `i128`.
pub fn mtimeNs(ioh: anytype, path: []const u8) ?i128 {
    if (comptime has_io) {
        const st = std.Io.Dir.cwd().statFile(ioh, path, .{}) catch return null;
        return @as(i128, st.mtime.nanoseconds);
    } else {
        const st = std.fs.cwd().statFile(path) catch return null;
        return st.mtime;
    }
}

// ------------------------------------------------------------------ processes

/// Spawn a child process. On 0.16 spawning is a `std.process` free function
/// taking an `Io` and an environment map; on the older versions it is
/// `Child.init` plus `spawn`.
pub fn spawn(ioh: anytype, env: anytype, alloc: std.mem.Allocator, argv: []const []const u8) !std.process.Child {
    if (comptime has_io) {
        return std.process.spawn(ioh, .{ .argv = argv, .environ_map = env });
    } else {
        var ch = std.process.Child.init(argv, alloc);
        try ch.spawn();
        return ch;
    }
}

/// Wait for a child and return its exit code. Any abnormal exit maps to 1.
/// 0.16 renamed the `Term` tags to lowercase.
pub fn wait(ioh: anytype, ch: *std.process.Child) !u8 {
    const term = if (comptime has_io) try ch.wait(ioh) else try ch.wait();
    if (comptime has_io) {
        return switch (term) {
            .exited => |code| code,
            else => 1,
        };
    } else {
        return switch (term) {
            .Exited => |code| code,
            else => 1,
        };
    }
}

/// Sleep for a number of milliseconds.
pub fn sleepMs(ioh: anytype, ms: u64) void {
    if (comptime has_io) {
        std.Io.sleep(ioh, std.Io.Duration.fromNanoseconds(@intCast(ms * std.time.ns_per_ms)), .awake) catch {};
    } else {
        std.Thread.sleep(ms * std.time.ns_per_ms);
    }
}

// ------------------------------------------------------------- build-time env

/// An environment variable, or null if unset. Caller owns the returned memory.
/// 0.16 removed `getEnvVarOwned` and keeps the environment on the build graph.
pub fn buildEnv(b: *std.Build, name: []const u8) ?[]const u8 {
    if (comptime @hasDecl(std.process, "getEnvVarOwned")) {
        return std.process.getEnvVarOwned(b.allocator, name) catch null;
    } else {
        const borrowed = b.graph.environ_map.get(name) orelse return null;
        return b.allocator.dupe(u8, borrowed) catch null;
    }
}

// ------------------------------------------------------------------- tests

test "filesystem roundtrip through the adaptor" {
    const ioh = io();
    const dir = "compat-test-tmp";
    makePath(ioh, dir);
    defer {
        if (comptime has_io) {
            std.Io.Dir.cwd().deleteTree(ioh, dir) catch {};
        } else {
            std.fs.cwd().deleteTree(dir) catch {};
        }
    }
    const path = dir ++ "/f.txt";
    try writeFile(ioh, path, "hello adaptor");
    try std.testing.expect(exists(ioh, path));
    try std.testing.expect(!exists(ioh, dir ++ "/missing"));

    const back = readFile(ioh, std.testing.allocator, path) orelse return error.ReadFailed;
    defer std.testing.allocator.free(back);
    try std.testing.expectEqualStrings("hello adaptor", back);

    try std.testing.expect(mtimeNs(ioh, path) != null);
    try std.testing.expect(mtimeNs(ioh, dir ++ "/missing") == null);
}
