const std = @import("std");
const builtin = @import("builtin");

/// Zig 0.16 moved the filesystem, stdio and process spawning under `std.Io`,
/// which took `File` out of `std.fs`. Only the taken branch of a
/// comptime-known `if` is analysed, so both spellings can coexist below.
const on_016 = !@hasDecl(std.fs, "File");

/// This CLI is synchronous and single threaded, so std's hardcoded blocking
/// implementation is the right one. 0.16 only.
fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// Zig 0.14 spells these `std.io.getStdOut()` / `std.io.getStdErr()`; Zig 0.15
/// removed `std.io.getStd*` and made the unbuffered `File.writer` take a
/// buffer; Zig 0.16 replaced the writer with the `std.Io.Writer` interface.
const StdWriter = if (on_016)
    *std.Io.Writer
else if (@hasDecl(std.fs.File, "DeprecatedWriter"))
    std.fs.File.DeprecatedWriter
else
    std.fs.File.Writer;

/// 0.16 only. The `File.Writer` has to outlive the interface pointer handed
/// back, and an empty buffer keeps the writes unbuffered like the old ones.
const std_streams = struct {
    var out: std.Io.File.Writer = undefined;
    var err: std.Io.File.Writer = undefined;
};

fn stdoutWriter() StdWriter {
    if (comptime on_016) {
        std_streams.out = std.Io.File.stdout().writerStreaming(io(), &.{});
        return &std_streams.out.interface;
    } else {
        const f = if (@hasDecl(std.fs.File, "stdout")) std.fs.File.stdout() else std.io.getStdOut();
        return if (@hasDecl(std.fs.File, "deprecatedWriter")) f.deprecatedWriter() else f.writer();
    }
}

fn stderrWriter() StdWriter {
    if (comptime on_016) {
        std_streams.err = std.Io.File.stderr().writerStreaming(io(), &.{});
        return &std_streams.err.interface;
    } else {
        const f = if (@hasDecl(std.fs.File, "stderr")) std.fs.File.stderr() else std.io.getStdErr();
        return if (@hasDecl(std.fs.File, "deprecatedWriter")) f.deprecatedWriter() else f.writer();
    }
}

/// True when `path` exists relative to the current directory.
fn pathExists(path: []const u8) bool {
    if (comptime on_016) {
        std.Io.Dir.cwd().access(io(), path, .{}) catch return false;
        return true;
    } else {
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }
}

/// Create `path` and any missing parents.
fn makePath(path: []const u8) !void {
    if (comptime on_016) {
        try std.Io.Dir.cwd().createDirPath(io(), path);
    } else {
        try std.fs.cwd().makePath(path);
    }
}

/// Delete a directory tree if it is there. Returns whether anything was removed.
pub fn removeTreeIfExists(path: []const u8) !bool {
    if (!pathExists(path)) return false;
    if (comptime on_016) {
        try std.Io.Dir.cwd().deleteTree(io(), path);
    } else {
        try std.fs.cwd().deleteTree(path);
    }
    return true;
}

/// Delete a single file, ignoring "not found" and any other error. Used to
/// clean up a probe file, where a failure to remove it is not worth surfacing.
fn deleteFileBestEffort(path: []const u8) void {
    if (comptime on_016) {
        std.Io.Dir.cwd().deleteFile(io(), path) catch {};
    } else {
        std.fs.cwd().deleteFile(path) catch {};
    }
}

/// True when a file can be written into `path`. It creates the directory if it
/// is missing, which is what Zig does with a cache directory on the next build,
/// then writes and removes a probe file. A read-only or unwritable directory
/// fails the write and reports false.
fn dirWritable(allocator: std.mem.Allocator, path: []const u8) bool {
    if (path.len == 0) return false;
    makePath(path) catch return false;
    const probe = std.fs.path.join(allocator, &.{ path, ".zaza-write-probe" }) catch return false;
    defer allocator.free(probe);
    writeFile(probe, "") catch return false;
    deleteFileBestEffort(probe);
    return true;
}

/// Zig 0.14 and 0.15 read the current process environment with
/// `getEnvVarOwned`. Zig 0.16 removed it: the environment arrives through the
/// entry point instead, so callers pass the `EnvMap` built from it. `env` is
/// that map on 0.16 and an unused void on the older versions.
const has_env_owned = @hasDecl(std.process, "getEnvVarOwned");

fn getEnvOwned(env: anytype, allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    if (comptime has_env_owned) {
        return std.process.getEnvVarOwned(allocator, name) catch null;
    } else {
        const borrowed = env.get(name) orelse return null;
        return allocator.dupe(u8, borrowed) catch null;
    }
}

/// `std.json.stringifyAlloc` (Zig 0.14) became `std.json.Stringify.valueAlloc` (Zig 0.15).
fn jsonStringifyIndent2(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    if (@hasDecl(std.json, "Stringify")) {
        return std.json.Stringify.valueAlloc(allocator, value, .{ .whitespace = .indent_2 });
    } else {
        return std.json.stringifyAlloc(allocator, value, .{ .whitespace = .indent_2 });
    }
}

/// Zig 0.16 removed `std.process.argsAlloc`; argv now arrives through the
/// entry point's parameter, which the older versions do not accept. Selecting
/// the entry point at comptime keeps one `run` body for all three.
pub const main = if (on_016) main016 else mainLegacy;

fn mainLegacy() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Legacy reads the environment through getEnvVarOwned, so nothing to pass.
    try run(allocator, args, {});
}

fn main016(init: std.process.Init.Minimal) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const args = try init.args.toSlice(arena.allocator());

    // 0.16 hands the environment to the entry point rather than exposing a
    // global accessor, so build the map here and pass it down.
    var env_map = try init.environ.createMap(allocator);
    defer env_map.deinit();
    try run(allocator, args, &env_map);
}

fn run(allocator: std.mem.Allocator, args: []const [:0]const u8, env: anytype) !void {
    if (args.len < 2) return usage();

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "fetch") or std.mem.eql(u8, cmd, "add")) {
        if (args.len < 3) return usage();
        const name = args[2];
        const zon_path = "build.zig.zon";
        const registry_path = "registry/registry.json";
        try fetchIntoZon(allocator, registry_path, zon_path, name);
        return;
    }

    if (std.mem.eql(u8, cmd, "list") or std.mem.eql(u8, cmd, "ls")) {
        const registry_path = "registry/registry.json";
        try listPackages(allocator, registry_path);
        return;
    }

    if (std.mem.eql(u8, cmd, "deps")) {
        try listCurrentDependencies(allocator, "build.zig.zon", "zaza.lock");
        return;
    }

    if (std.mem.eql(u8, cmd, "lock")) {
        const check = args.len >= 3 and std.mem.eql(u8, args[2], "--check");
        if (check) {
            try lockCheck(allocator, "build.zig.zon", "zaza.lock");
        } else {
            try lockReconcile(allocator, "build.zig.zon", "zaza.lock");
        }
        return;
    }

    if (std.mem.eql(u8, cmd, "clean-deps") or std.mem.eql(u8, cmd, "clean")) {
        try cleanDeps(allocator);
        return;
    }

    if (std.mem.eql(u8, cmd, "cache")) {
        try cacheInfo(env, allocator);
        return;
    }

    if (std.mem.eql(u8, cmd, "doctor")) {
        try doctor(env, allocator);
        return;
    }

    if (std.mem.eql(u8, cmd, "graph")) {
        try graphDot(allocator, "build.zig.zon");
        return;
    }

    if (std.mem.eql(u8, cmd, "remove") or std.mem.eql(u8, cmd, "rm")) {
        if (args.len < 3) return usage();
        const name = args[2];
        const zon_path = "build.zig.zon";
        try removeDependency(allocator, zon_path, name);
        return;
    }

    if (std.mem.eql(u8, cmd, "init")) {
        const project_name = if (args.len >= 3) args[2] else "my-zaza-project";
        try initProject(allocator, project_name);
        return;
    }

    if (std.mem.eql(u8, cmd, "search")) {
        if (args.len < 3) return usage();
        const query = args[2];
        const registry_path = "registry/registry.json";
        try searchPackages(allocator, registry_path, query);
        return;
    }

    if (std.mem.eql(u8, cmd, "info") or std.mem.eql(u8, cmd, "show")) {
        if (args.len < 3) return usage();
        const name = args[2];
        const registry_path = "registry/registry.json";
        try infoPackage(allocator, registry_path, name);
        return;
    }

    return usage();
}

fn usage() !void {
    const stderr = stderrWriter();
    try stderr.print(
        \\Usage:
        \\  zaza fetch <name>    Fetch a package from the registry into build.zig.zon (alias: add)
        \\  zaza add <name>      Alias for fetch
        \\  zaza remove <name>   Remove a dependency from build.zig.zon (alias: rm)
        \\  zaza list            List all packages available in the registry (alias: ls)
        \\  zaza deps            List dependencies with source, lock state, and on-disk presence
        \\  zaza graph           Print the dependency graph as Graphviz DOT (pipe to `dot`)
        \\  zaza lock            Regenerate zaza.lock from build.zig.zon
        \\  zaza lock --check    Verify zaza.lock matches build.zig.zon (fails on drift; for CI)
        \\  zaza clean-deps      Remove deps/ and zig-out/deps (alias: clean)
        \\  zaza cache           Show the Zig cache directories and whether they are writable
        \\  zaza doctor          Check the Zig lane, caches, and dependency lock; fails on a problem
        \\  zaza search <query>  Search packages by name, description, and keywords (ranked)
        \\  zaza info <name>     Show full metadata for a package (alias: show)
        \\  zaza init [name]     Scaffold a new Zaza project in the current directory
        \\
        , .{},
    );
    return error.InvalidArgs;
}

fn fetchIntoZon(
    allocator: std.mem.Allocator,
    registry_path: []const u8,
    zon_path: []const u8,
    name: []const u8,
) !void {
    const registry = try readFile(allocator, registry_path);
    defer allocator.free(registry);

    const url = try lookupRegistryUrl(allocator, registry, name);
    defer allocator.free(url);

    const hash = try zigFetch(allocator, url);
    defer allocator.free(hash);

    const zon = try readFile(allocator, zon_path);
    defer allocator.free(zon);

    const updated = try upsertDependency(allocator, zon, name, url, hash);
    defer allocator.free(updated);

    try writeFile(zon_path, updated);
    try updateLock(allocator, "zaza.lock", name, url, hash);

    const stdout = stdoutWriter();
    try stdout.print("added {s}\n", .{name});
}

fn lookupRegistryUrl(allocator: std.mem.Allocator, data: []const u8, name: []const u8) ![]const u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const packages = root.object.get("packages") orelse return error.PackageNotFound;
    const entry = packages.object.get(name) orelse return error.PackageNotFound;
    const url = entry.object.get("url") orelse return error.PackageNotFound;
    if (url.string.len == 0) return error.PackageNotFound;
    return allocator.dupe(u8, url.string);
}

fn zigFetch(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    // Both arms pipe stdout and inherit stderr so `zig fetch` progress still
    // reaches the terminal while the hash is captured.
    const out = if (comptime on_016) blk: {
        var child = try std.process.spawn(io(), .{
            .argv = &.{ "zig", "fetch", url },
            .stdout = .pipe,
            .stderr = .inherit,
        });
        var reader = child.stdout.?.readerStreaming(io(), &.{});
        const captured = try reader.interface.allocRemaining(allocator, .limited(16 * 1024));
        errdefer allocator.free(captured);
        switch (try child.wait(io())) {
            .exited => |code| if (code != 0) return error.CommandFailed,
            else => return error.CommandFailed,
        }
        break :blk captured;
    } else blk: {
        var child = std.process.Child.init(&.{ "zig", "fetch", url }, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Inherit;
        try child.spawn();

        const captured = try child.stdout.?.readToEndAlloc(allocator, 16 * 1024);
        errdefer allocator.free(captured);
        switch (try child.wait()) {
            .Exited => |code| if (code != 0) return error.CommandFailed,
            else => return error.CommandFailed,
        }
        break :blk captured;
    };
    defer allocator.free(out);

    const trimmed = std.mem.trim(u8, out, " \t\r\n");
    return allocator.dupe(u8, trimmed);
}

pub fn upsertDependency(
    allocator: std.mem.Allocator,
    zon: []const u8,
    name: []const u8,
    url: []const u8,
    hash: []const u8,
) ![]const u8 {
    const dep_marker = ".dependencies = .{";
    const idx = std.mem.indexOf(u8, zon, dep_marker) orelse return error.MissingDependencies;

    const start = idx + dep_marker.len;
    const end = findMatchingBrace(zon, start) orelse return error.BadZonFormat;

    const dep_block = zon[start..end];
    const needle = try std.fmt.allocPrint(allocator, ".{s}", .{name});
    defer allocator.free(needle);
    if (std.mem.indexOf(u8, dep_block, needle) != null) {
        return allocator.dupe(u8, zon);
    }

    const entry = try std.fmt.allocPrint(
        allocator,
        "\n        .{s} = .{{\n            .url = \"{s}\",\n            .hash = \"{s}\",\n        }},\n",
        .{ name, url, hash },
    );
    defer allocator.free(entry);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.appendSlice(allocator, zon[0..start]);
    try out.appendSlice(allocator, entry);
    try out.appendSlice(allocator, zon[start..]);
    return out.toOwnedSlice(allocator);
}

fn findMatchingBrace(data: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var i = start;
    while (i < data.len) : (i += 1) {
        const c = data[i];
        if (c == '{') depth += 1;
        if (c == '}') {
            if (depth == 0) return i;
            depth -= 1;
        }
    }
    return null;
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (comptime on_016) {
        return std.Io.Dir.cwd().readFileAlloc(io(), path, allocator, .unlimited);
    } else {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const size = (try file.stat()).size;
        const buf = try allocator.alloc(u8, size);
        _ = try file.readAll(buf);
        return buf;
    }
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    if (comptime on_016) {
        try std.Io.Dir.cwd().writeFile(io(), .{ .sub_path = path, .data = data });
    } else {
        const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
    }
}

/// Read a string field from a registry entry object, returning "" when the
/// field is missing or is not a string. Extra fields are ignored, so a v1
/// entry (only version + url) and a v2 entry (with description, keywords,
/// repo, homepage, license) both read cleanly.
fn jsonStr(obj: std.json.Value, key: []const u8) []const u8 {
    const v = obj.object.get(key) orelse return "";
    return switch (v) {
        .string => |s| s,
        else => "",
    };
}

fn versionOrUnknown(entry: std.json.Value) []const u8 {
    const v = jsonStr(entry, "version");
    return if (v.len > 0) v else "?";
}

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (prefix.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

/// Score how well a package matches a search query. Higher is a better match;
/// zero means no match. The score blends name, keywords and description so a
/// user can find a package by what it does, without knowing its exact name.
/// The strongest single signal wins rather than summing, which keeps an exact
/// name match ahead of a package that merely mentions the term in prose.
pub fn matchScore(
    name: []const u8,
    description: []const u8,
    keywords: []const []const u8,
    query: []const u8,
) usize {
    if (query.len == 0) return 0;
    var best: usize = 0;

    if (std.ascii.eqlIgnoreCase(name, query)) {
        best = @max(best, 100);
    } else if (startsWithIgnoreCase(name, query)) {
        best = @max(best, 80);
    } else if (std.ascii.indexOfIgnoreCase(name, query) != null) {
        best = @max(best, 60);
    }

    for (keywords) |kw| {
        if (std.ascii.eqlIgnoreCase(kw, query)) {
            best = @max(best, 55);
        } else if (std.ascii.indexOfIgnoreCase(kw, query) != null) {
            best = @max(best, 40);
        }
    }

    if (std.ascii.indexOfIgnoreCase(description, query) != null) {
        best = @max(best, 25);
    }

    return best;
}

fn listPackages(allocator: std.mem.Allocator, registry_path: []const u8) !void {
    const registry = readFile(allocator, registry_path) catch {
        const stderr = stderrWriter();
        try stderr.print("error: registry not found at {s}\n", .{registry_path});
        return error.RegistryNotFound;
    };
    defer allocator.free(registry);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, registry, .{});
    defer parsed.deinit();

    const packages = parsed.value.object.get("packages") orelse return error.InvalidRegistry;
    const stdout = stdoutWriter();
    try stdout.print("Available packages ({d}):\n", .{packages.object.count()});
    var it = packages.object.iterator();
    while (it.next()) |entry| {
        const version = versionOrUnknown(entry.value_ptr.*);
        const description = jsonStr(entry.value_ptr.*, "description");
        if (description.len > 0) {
            try stdout.print("  {s:<16} {s:<10} {s}\n", .{ entry.key_ptr.*, version, description });
        } else {
            try stdout.print("  {s:<16} {s}\n", .{ entry.key_ptr.*, version });
        }
    }
}

const Match = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    score: usize,
};

fn matchLessThan(_: void, a: Match, b: Match) bool {
    if (a.score != b.score) return a.score > b.score;
    return std.mem.lessThan(u8, a.name, b.name);
}

fn searchPackages(allocator: std.mem.Allocator, registry_path: []const u8, query: []const u8) !void {
    const registry = readFile(allocator, registry_path) catch {
        const stderr = stderrWriter();
        try stderr.print("error: registry not found at {s}\n", .{registry_path});
        return error.RegistryNotFound;
    };
    defer allocator.free(registry);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, registry, .{});
    defer parsed.deinit();

    const packages = parsed.value.object.get("packages") orelse return error.InvalidRegistry;

    // Slices below borrow from the parsed tree, which lives to the end of the
    // function; the arena only owns the small bookkeeping arrays.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var matches: std.ArrayListUnmanaged(Match) = .empty;

    var it = packages.object.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const val = entry.value_ptr.*;
        const description = jsonStr(val, "description");

        var keywords: std.ArrayListUnmanaged([]const u8) = .empty;
        if (val.object.get("keywords")) |kv| switch (kv) {
            .array => |arr| for (arr.items) |item| switch (item) {
                .string => |s| try keywords.append(a, s),
                else => {},
            },
            else => {},
        };

        const score = matchScore(name, description, keywords.items, query);
        if (score > 0) {
            try matches.append(a, .{
                .name = name,
                .version = versionOrUnknown(val),
                .description = description,
                .score = score,
            });
        }
    }

    std.mem.sort(Match, matches.items, {}, matchLessThan);

    const stdout = stdoutWriter();
    if (matches.items.len == 0) {
        try stdout.print("No packages matching '{s}'\n", .{query});
        return;
    }
    try stdout.print("Packages matching '{s}' ({d}):\n", .{ query, matches.items.len });
    for (matches.items) |m| {
        if (m.description.len > 0) {
            try stdout.print("  {s:<16} {s:<10} {s}\n", .{ m.name, m.version, m.description });
        } else {
            try stdout.print("  {s:<16} {s}\n", .{ m.name, m.version });
        }
    }
}

fn printField(stdout: StdWriter, label: []const u8, value: []const u8) !void {
    if (value.len == 0) return;
    try stdout.print("  {s:<10}{s}\n", .{ label, value });
}

fn infoPackage(allocator: std.mem.Allocator, registry_path: []const u8, name: []const u8) !void {
    const registry = readFile(allocator, registry_path) catch {
        const stderr = stderrWriter();
        try stderr.print("error: registry not found at {s}\n", .{registry_path});
        return error.RegistryNotFound;
    };
    defer allocator.free(registry);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, registry, .{});
    defer parsed.deinit();

    const packages = parsed.value.object.get("packages") orelse return error.InvalidRegistry;
    const entry = packages.object.get(name) orelse {
        const stderr = stderrWriter();
        try stderr.print("error: no package named '{s}' in the registry\n", .{name});
        try stderr.print("try: zaza search {s}\n", .{name});
        return error.PackageNotFound;
    };

    const stdout = stdoutWriter();
    try stdout.print("{s}  {s}\n", .{ name, versionOrUnknown(entry) });

    const description = jsonStr(entry, "description");
    if (description.len > 0) try stdout.print("  {s}\n", .{description});

    try printField(stdout, "license", jsonStr(entry, "license"));
    try printField(stdout, "repo", jsonStr(entry, "repo"));
    try printField(stdout, "homepage", jsonStr(entry, "homepage"));

    if (entry.object.get("keywords")) |kv| switch (kv) {
        .array => |arr| if (arr.items.len > 0) {
            try stdout.print("  {s:<10}", .{"keywords"});
            var first = true;
            for (arr.items) |item| switch (item) {
                .string => |s| {
                    if (!first) try stdout.print(", ", .{});
                    try stdout.print("{s}", .{s});
                    first = false;
                },
                else => {},
            };
            try stdout.print("\n", .{});
        },
        else => {},
    };

    try printField(stdout, "url", jsonStr(entry, "url"));
}

pub fn removeDependency(allocator: std.mem.Allocator, zon_path: []const u8, name: []const u8) !void {
    const zon = try readFile(allocator, zon_path);
    defer allocator.free(zon);

    // Find the entry: .name = .{ ... },
    const needle = try std.fmt.allocPrint(allocator, ".{s} = .{{", .{name});
    defer allocator.free(needle);

    const start = std.mem.indexOf(u8, zon, needle) orelse {
        const stderr = stderrWriter();
        try stderr.print("error: dependency '{s}' not found in {s}\n", .{ name, zon_path });
        return error.DependencyNotFound;
    };

    // Walk back to the start of the line (handles leading whitespace)
    var line_start = start;
    while (line_start > 0 and zon[line_start - 1] != '\n') {
        line_start -= 1;
    }

    // Walk forward to find the matching closing brace, then consume the trailing comma + newline
    const block_start = start + needle.len - 1; // position of the opening '{'
    const block_end = findMatchingBrace(zon, block_start + 1) orelse return error.BadZonFormat;

    // Consume the trailing comma and newline after the closing brace
    var remove_end = block_end + 1;
    if (remove_end < zon.len and zon[remove_end] == ',') remove_end += 1;
    while (remove_end < zon.len and (zon[remove_end] == '\n' or zon[remove_end] == '\r')) {
        remove_end += 1;
    }

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, zon[0..line_start]);
    try out.appendSlice(allocator, zon[remove_end..]);
    try writeFile(zon_path, out.items);
    removeLockEntry(allocator, "zaza.lock", name) catch {};

    const stdout = stdoutWriter();
    try stdout.print("removed {s}\n", .{name});
}

fn initProject(allocator: std.mem.Allocator, name: []const u8) !void {
    const stdout = stdoutWriter();

    // Check if build.zig.zon already exists
    if (pathExists("build.zig.zon")) {
        const stderr = stderrWriter();
        try stderr.print("error: build.zig.zon already exists. Remove it first.\n", .{});
        return error.AlreadyExists;
    }

    // Write build.zig.zon
    const zon = try std.fmt.allocPrint(allocator,
        \\.{{
        \\    .name = .{s},
        \\    .version = "0.1.0",
        \\    .minimum_zig_version = "0.14.0",
        \\    .dependencies = .{{}},
        \\    .paths = .{{
        \\        "build.zig",
        \\        "build.zig.zon",
        \\        "src",
        \\    }},
        \\}}
        \\
    , .{name});
    defer allocator.free(zon);
    try writeFile("build.zig.zon", zon);

    // Write build.zig
    const build_zig =
        \\const std = @import("std");
        \\const cpp = @import("build_lib/cpp_example.zig");
        \\
        \\pub fn build(b: *std.Build) !void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "app",
        \\        .root_module = b.createModule(.{
        \\            .optimize = optimize,
        \\            .target = target,
        \\        }),
        \\    });
        \\    exe.addCSourceFile(.{ .file = b.path("src/main.cpp"), .flags = &.{"-std=c++17"} });
        \\    b.installArtifact(exe);
        \\
        \\    const run = b.addRunArtifact(exe);
        \\    const run_step = b.step("run", "Run the app");
        \\    run_step.dependOn(&run.step);
        \\}
        \\
    ;
    if (pathExists("build.zig")) {
        try stdout.print("  (skipped build.zig — already exists)\n", .{});
    } else {
        try writeFile("build.zig", build_zig);
    }

    // Create src/main.cpp
    try makePath("src");
    const main_cpp =
        \\#include <iostream>
        \\
        \\int main() {
        \\    std::cout << "Hello from Zaza!\n";
        \\    return 0;
        \\}
        \\
    ;
    if (pathExists("src/main.cpp")) {
        try stdout.print("  (skipped src/main.cpp — already exists)\n", .{});
    } else {
        try writeFile("src/main.cpp", main_cpp);
    }

    try stdout.print("initialized project '{s}'\n", .{name});
    try stdout.print("  build.zig.zon   created\n", .{});
    try stdout.print("  build.zig       created\n", .{});
    try stdout.print("  src/main.cpp    created\n", .{});
    try stdout.print("\nNext: zig build run\n", .{});
}

/// Zig 0.16 made `std.json.ObjectMap` unmanaged: it no longer carries its
/// allocator, so construction and insertion both changed shape. The managed
/// form keeps an `allocator` field, which is what these branch on.
const json_object_managed = @hasField(std.json.ObjectMap, "allocator");

fn emptyJsonObject(gpa: std.mem.Allocator) std.json.Value {
    if (comptime json_object_managed) {
        return .{ .object = std.json.ObjectMap.init(gpa) };
    } else {
        return .{ .object = .empty };
    }
}

fn jsonObjectPut(
    obj: *std.json.ObjectMap,
    gpa: std.mem.Allocator,
    key: []const u8,
    value: std.json.Value,
) !void {
    if (comptime json_object_managed) {
        try obj.put(key, value);
    } else {
        try obj.put(gpa, key, value);
    }
}

pub fn updateLock(allocator: std.mem.Allocator, path: []const u8, name: []const u8, url: []const u8, hash: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const lock_data = readFile(arena_alloc, path) catch
        try arena_alloc.dupe(u8, "{\n  \"packages\": {}\n}\n");

    var parsed = try std.json.parseFromSlice(std.json.Value, arena_alloc, lock_data, .{});
    defer parsed.deinit();
    var root = parsed.value;
    if (root.object.getPtr("packages") == null) {
        try jsonObjectPut(&root.object, arena_alloc, "packages", emptyJsonObject(arena_alloc));
    }
    const packages = root.object.getPtr("packages").?;

    var entry = emptyJsonObject(arena_alloc);
    try jsonObjectPut(&entry.object, arena_alloc, "name", .{ .string = name });
    try jsonObjectPut(&entry.object, arena_alloc, "source", .{ .string = "registry" });
    try jsonObjectPut(&entry.object, arena_alloc, "url", .{ .string = url });
    try jsonObjectPut(&entry.object, arena_alloc, "hash", .{ .string = hash });
    try jsonObjectPut(&packages.object, arena_alloc, name, entry);

    const json_text = try jsonStringifyIndent2(arena_alloc, root);
    defer arena_alloc.free(json_text);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(arena_alloc);
    try out.appendSlice(arena_alloc, json_text);
    try out.append(arena_alloc, '\n');
    try writeFile(path, out.items);
}

pub fn removeLockEntry(allocator: std.mem.Allocator, path: []const u8, name: []const u8) !void {
    const lock_data = readFile(allocator, path) catch return;
    defer allocator.free(lock_data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, lock_data, .{});
    defer parsed.deinit();
    const packages = parsed.value.object.getPtr("packages") orelse return;
    _ = packages.object.orderedRemove(name);

    const json_text = try jsonStringifyIndent2(allocator, parsed.value);
    defer allocator.free(json_text);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, json_text);
    try out.append(allocator, '\n');
    try writeFile(path, out.items);
}

fn cleanDeps(allocator: std.mem.Allocator) !void {
    _ = allocator;
    const stdout = stdoutWriter();
    // deps/ holds fetched sources; zig-out/deps holds their built outputs.
    const targets = [_][]const u8{ "deps", "zig-out/deps" };
    var removed_any = false;
    for (targets) |target| {
        const removed = removeTreeIfExists(target) catch |err| {
            const stderr = stderrWriter();
            try stderr.print("error: could not remove {s}: {s}\n", .{ target, @errorName(err) });
            return err;
        };
        if (removed) {
            try stdout.print("removed {s}\n", .{target});
            removed_any = true;
        }
    }
    if (!removed_any) {
        try stdout.print("nothing to remove: deps/ and zig-out/deps are already absent\n", .{});
    }
}

fn cacheInfo(env: anytype, allocator: std.mem.Allocator) !void {
    const stdout = stdoutWriter();
    try stdout.print("Zig cache directories:\n", .{});

    if (getEnvOwned(env, allocator, "ZIG_GLOBAL_CACHE_DIR")) |path| {
        defer allocator.free(path);
        const state = if (dirWritable(allocator, path)) "writable" else "not writable";
        try stdout.print("  global   {s}  ({s})\n", .{ path, state });
    } else {
        try stdout.print("  global   unset  (Zig uses its per-user default; set ZIG_GLOBAL_CACHE_DIR to override)\n", .{});
    }

    // The local cache defaults to .zig-cache in the working directory.
    if (getEnvOwned(env, allocator, "ZIG_LOCAL_CACHE_DIR")) |path| {
        defer allocator.free(path);
        const state = if (dirWritable(allocator, path)) "writable" else "not writable";
        try stdout.print("  local    {s}  ({s})\n", .{ path, state });
    } else {
        const default_local = ".zig-cache";
        const state = if (pathExists(default_local))
            (if (dirWritable(allocator, default_local)) "writable" else "not writable")
        else
            "absent, created on first build";
        try stdout.print("  local    {s} (default)  ({s})\n", .{ default_local, state });
    }
}

const LockState = union(enum) {
    in_sync: usize,
    drift: usize,
    no_lock,
    no_manifest,
};

/// Summarise how the lock relates to the manifest. Carries only counts, so the
/// arena it reads through can be freed before the result is used.
fn lockState(allocator: std.mem.Allocator) LockState {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const zon = readFile(a, "build.zig.zon") catch return .no_manifest;
    const lock = readFile(a, "zaza.lock") catch return .no_lock;
    const drifts = lockDrift(a, zon, lock) catch return .{ .drift = 0 };
    if (drifts.len > 0) return .{ .drift = drifts.len };
    const deps = parseZonDependencies(a, zon) catch return .{ .in_sync = 0 };
    return .{ .in_sync = deps.len };
}

/// One command that checks a project is ready to build: the Zig lane, the cache
/// directories, and whether the dependency lock agrees with the manifest.
/// Exits non-zero when a check needs attention, so it doubles as a CI gate.
fn doctor(env: anytype, allocator: std.mem.Allocator) !void {
    const stdout = stdoutWriter();
    try stdout.print("zaza doctor\n", .{});
    var ok = true;

    // Zig lane: Zaza is validated on 0.14, 0.15, and 0.16.
    const v = builtin.zig_version;
    const supported = v.major == 0 and v.minor >= 14 and v.minor <= 16;
    const lane_status = if (supported) "supported" else "unsupported: use 0.14, 0.15, or 0.16";
    try stdout.print("  zig              {d}.{d}.{d}  ({s})\n", .{ v.major, v.minor, v.patch, lane_status });
    if (!supported) ok = false;

    // Global cache.
    if (getEnvOwned(env, allocator, "ZIG_GLOBAL_CACHE_DIR")) |path| {
        defer allocator.free(path);
        const w = dirWritable(allocator, path);
        try stdout.print("  global cache     {s}  ({s})\n", .{ path, if (w) "writable" else "not writable" });
        if (!w) ok = false;
    } else {
        try stdout.print("  global cache     unset  (Zig uses its per-user default)\n", .{});
    }

    // Local cache.
    {
        const local = getEnvOwned(env, allocator, "ZIG_LOCAL_CACHE_DIR");
        defer if (local) |p| allocator.free(p);
        const path = local orelse ".zig-cache";
        const w = dirWritable(allocator, path);
        try stdout.print("  local cache      {s}  ({s})\n", .{ path, if (w) "writable" else "not writable" });
        if (!w) ok = false;
    }

    // Dependency lock.
    switch (lockState(allocator)) {
        .in_sync => |n| try stdout.print("  dependency lock  in sync ({d} dependencies)\n", .{n}),
        .drift => |n| {
            try stdout.print("  dependency lock  {d} difference(s): run `zaza lock`\n", .{n});
            ok = false;
        },
        .no_lock => try stdout.print("  dependency lock  zaza.lock absent: run `zaza lock`\n", .{}),
        .no_manifest => try stdout.print("  dependency lock  no build.zig.zon in this directory\n", .{}),
    }

    try stdout.print("\n{s}\n", .{if (ok) "all checks passed" else "some checks need attention"});
    if (!ok) return error.DoctorChecksFailed;
}

pub fn parseDependencyNames(allocator: std.mem.Allocator, zon: []const u8) ![][]const u8 {
    const dep_marker = ".dependencies = .{";
    const idx = std.mem.indexOf(u8, zon, dep_marker) orelse return allocator.alloc([]const u8, 0);
    const start = idx + dep_marker.len;
    const end = findMatchingBrace(zon, start) orelse return error.BadZonFormat;
    const dep_block = zon[start..end];

    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, dep_block, "\n");
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r,");
        if (!std.mem.startsWith(u8, trimmed, ".")) continue;
        if (std.mem.indexOf(u8, trimmed, " = .{")) |eq_idx| {
            try names.append(allocator, try allocator.dupe(u8, trimmed[1..eq_idx]));
        }
    }
    return names.toOwnedSlice(allocator);
}

pub const LockEntry = struct {
    /// Where the dependency came from, e.g. "registry". Empty when the lock
    /// recorded no source. Owned by the caller.
    source: []u8,
    /// The recorded content hash. Empty when absent. Owned by the caller.
    hash: []u8,
};

/// Look up a dependency's recorded source and hash in the lock file contents.
/// Returns null when the name is not locked. The caller frees the returned
/// slices.
pub fn lockEntryInfo(allocator: std.mem.Allocator, lock_data: []const u8, name: []const u8) !?LockEntry {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, lock_data, .{});
    defer parsed.deinit();

    const packages = parsed.value.object.get("packages") orelse return null;
    const entry = packages.object.get(name) orelse return null;
    const source = if (entry.object.get("source")) |s| s.string else "";
    const hash = if (entry.object.get("hash")) |h| h.string else "";
    return LockEntry{
        .source = try allocator.dupe(u8, source),
        .hash = try allocator.dupe(u8, hash),
    };
}

pub fn listCurrentDependencies(allocator: std.mem.Allocator, zon_path: []const u8, lock_path: []const u8) !void {
    const zon = try readFile(allocator, zon_path);
    defer allocator.free(zon);
    const names = try parseDependencyNames(allocator, zon);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }

    const lock_data: ?[]u8 = readFile(allocator, lock_path) catch null;
    defer if (lock_data) |data| allocator.free(data);

    const stdout = stdoutWriter();
    try stdout.print("Dependencies ({d}):\n", .{names.len});
    if (names.len == 0) {
        try stdout.print("  (none declared in {s})\n", .{zon_path});
        return;
    }
    try stdout.print("  {s:<16} {s:<10} {s:<14} {s}\n", .{ "name", "source", "hash", "on disk" });

    for (names) |name| {
        const entry_opt: ?LockEntry = if (lock_data) |data|
            lockEntryInfo(allocator, data, name) catch null
        else
            null;
        defer if (entry_opt) |entry| {
            allocator.free(entry.source);
            allocator.free(entry.hash);
        };

        var source: []const u8 = "unlocked";
        var hash_disp: []const u8 = "-";
        if (entry_opt) |entry| {
            source = if (entry.source.len > 0) entry.source else "locked";
            if (entry.hash.len > 0) hash_disp = entry.hash[0..@min(entry.hash.len, 14)];
        }

        const dep_path = std.fs.path.join(allocator, &.{ "deps", name }) catch continue;
        defer allocator.free(dep_path);
        const on_disk = if (pathExists(dep_path)) "yes" else "no";

        try stdout.print("  {s:<16} {s:<10} {s:<14} {s}\n", .{ name, source, hash_disp, on_disk });
    }
}

/// One dependency read out of `build.zig.zon`: the pin the lock records. The
/// slices are owned by the caller (use an arena, or free each field).
pub const ZonDep = struct {
    name: []const u8,
    url: []const u8,
    hash: []const u8,
};

/// Extract `name`, `url`, and `hash` for every dependency in a `build.zig.zon`.
/// The manifest is the source of truth; the lock is derived from this. Missing
/// `url`/`hash` come back empty rather than failing, so a partially written
/// manifest still parses.
pub fn parseZonDependencies(allocator: std.mem.Allocator, zon: []const u8) ![]ZonDep {
    const names = try parseDependencyNames(allocator, zon);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }

    var deps = try allocator.alloc(ZonDep, names.len);
    errdefer allocator.free(deps);
    for (names, 0..) |name, i| {
        const marker = try std.fmt.allocPrint(allocator, ".{s} = .{{", .{name});
        defer allocator.free(marker);
        const marker_idx = std.mem.indexOf(u8, zon, marker) orelse return error.BadZonFormat;
        const block_start = marker_idx + marker.len;
        const block_end = findMatchingBrace(zon, block_start) orelse return error.BadZonFormat;
        const block = zon[block_start..block_end];
        deps[i] = .{
            .name = try allocator.dupe(u8, name),
            .url = try allocator.dupe(u8, zonStringField(block, "url") orelse ""),
            .hash = try allocator.dupe(u8, zonStringField(block, "hash") orelse ""),
        };
    }
    return deps;
}

/// Read the package name from a `build.zig.zon`. Handles the enum-literal form
/// (`.name = .zaza`) and the string form (`.name = "zaza"`).
pub fn parseZonName(zon: []const u8) ?[]const u8 {
    const marker = ".name = ";
    const idx = std.mem.indexOf(u8, zon, marker) orelse return null;
    var i = idx + marker.len;
    if (i >= zon.len) return null;
    if (zon[i] == '.') i += 1; // enum literal: .name = .zaza
    if (i < zon.len and zon[i] == '"') {
        const rest = zon[i + 1 ..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
        return rest[0..end];
    }
    var j = i;
    while (j < zon.len and (std.ascii.isAlphanumeric(zon[j]) or zon[j] == '_')) j += 1;
    if (j == i) return null;
    return zon[i..j];
}

/// Render the dependency graph as Graphviz DOT, the analogue of CMake's
/// `--graphviz`. The root package points at each dependency, which is labelled
/// with a short hash. Pipe the output to `dot` to render an image.
pub fn renderDepGraphDot(allocator: std.mem.Allocator, root: []const u8, deps: []const ZonDep) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "digraph zaza {\n  rankdir=LR;\n  node [shape=box];\n");
    const root_line = try std.fmt.allocPrint(allocator, "  \"{s}\" [style=bold];\n", .{root});
    defer allocator.free(root_line);
    try out.appendSlice(allocator, root_line);

    for (deps) |d| {
        const short = if (d.hash.len > 0) d.hash[0..@min(d.hash.len, 16)] else "";
        const node = try std.fmt.allocPrint(allocator, "  \"{s}\" [label=\"{s}\\n{s}\"];\n", .{ d.name, d.name, short });
        defer allocator.free(node);
        try out.appendSlice(allocator, node);
    }
    for (deps) |d| {
        const edge = try std.fmt.allocPrint(allocator, "  \"{s}\" -> \"{s}\";\n", .{ root, d.name });
        defer allocator.free(edge);
        try out.appendSlice(allocator, edge);
    }

    try out.appendSlice(allocator, "}\n");
    return out.toOwnedSlice(allocator);
}

/// Print the dependency graph of `zon_path` as Graphviz DOT.
fn graphDot(allocator: std.mem.Allocator, zon_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const zon = try readFile(a, zon_path);
    const root = parseZonName(zon) orelse "project";
    const deps = try parseZonDependencies(a, zon);
    const dot = try renderDepGraphDot(a, root, deps);

    const stdout = stdoutWriter();
    try stdout.print("{s}", .{dot});
}

/// Read a `.key = "value"` string field out of a zon block, or null when it is
/// absent.
fn zonStringField(block: []const u8, key: []const u8) ?[]const u8 {
    var buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, ".{s} = \"", .{key}) catch return null;
    const idx = std.mem.indexOf(u8, block, needle) orelse return null;
    const value_start = idx + needle.len;
    const rest = block[value_start..];
    const value_end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..value_end];
}

/// Render a `zaza.lock` from the manifest's dependencies. Entries keep the
/// manifest's order, so the same manifest always renders byte-for-byte the same
/// lock. The result is owned by the caller.
pub fn renderLock(allocator: std.mem.Allocator, deps: []const ZonDep) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var packages = emptyJsonObject(a);
    for (deps) |d| {
        var entry = emptyJsonObject(a);
        try jsonObjectPut(&entry.object, a, "name", .{ .string = d.name });
        try jsonObjectPut(&entry.object, a, "source", .{ .string = "registry" });
        try jsonObjectPut(&entry.object, a, "url", .{ .string = d.url });
        try jsonObjectPut(&entry.object, a, "hash", .{ .string = d.hash });
        try jsonObjectPut(&packages.object, a, d.name, entry);
    }
    var root = emptyJsonObject(a);
    try jsonObjectPut(&root.object, a, "packages", packages);

    const text = try jsonStringifyIndent2(a, root);
    var out = try allocator.alloc(u8, text.len + 1);
    @memcpy(out[0..text.len], text);
    out[text.len] = '\n';
    return out;
}

/// The names recorded in a lock's `packages` object. Owned by the caller.
pub fn lockPackageNames(allocator: std.mem.Allocator, lock_data: []const u8) ![][]const u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, lock_data, .{});
    defer parsed.deinit();

    const packages = parsed.value.object.get("packages") orelse return allocator.alloc([]const u8, 0);
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer names.deinit(allocator);
    var it = packages.object.iterator();
    while (it.next()) |kv| {
        try names.append(allocator, try allocator.dupe(u8, kv.key_ptr.*));
    }
    return names.toOwnedSlice(allocator);
}

/// How a lock entry disagrees with the manifest.
pub const DriftKind = enum { missing, hash_mismatch, extra };

/// One disagreement between the lock and the manifest. Owned by the caller.
pub const Drift = struct {
    name: []const u8,
    kind: DriftKind,
    manifest_hash: []const u8 = "",
    locked_hash: []const u8 = "",
};

/// Compare a manifest against a lock and return every disagreement: a manifest
/// dependency the lock is missing, a hash that differs, or a lock entry the
/// manifest no longer has. An empty result means the lock is in sync. The
/// returned slice and its strings are owned by the caller (use an arena).
pub fn lockDrift(allocator: std.mem.Allocator, zon: []const u8, lock_data: []const u8) ![]Drift {
    const deps = try parseZonDependencies(allocator, zon);
    defer {
        for (deps) |d| {
            allocator.free(d.name);
            allocator.free(d.url);
            allocator.free(d.hash);
        }
        allocator.free(deps);
    }

    var drifts: std.ArrayListUnmanaged(Drift) = .empty;
    errdefer drifts.deinit(allocator);

    for (deps) |d| {
        const entry = try lockEntryInfo(allocator, lock_data, d.name);
        if (entry) |e| {
            defer {
                allocator.free(e.source);
                allocator.free(e.hash);
            }
            if (!std.mem.eql(u8, e.hash, d.hash)) {
                try drifts.append(allocator, .{
                    .name = try allocator.dupe(u8, d.name),
                    .kind = .hash_mismatch,
                    .manifest_hash = try allocator.dupe(u8, d.hash),
                    .locked_hash = try allocator.dupe(u8, e.hash),
                });
            }
        } else {
            try drifts.append(allocator, .{
                .name = try allocator.dupe(u8, d.name),
                .kind = .missing,
                .manifest_hash = try allocator.dupe(u8, d.hash),
            });
        }
    }

    const lock_names = try lockPackageNames(allocator, lock_data);
    defer {
        for (lock_names) |n| allocator.free(n);
        allocator.free(lock_names);
    }
    for (lock_names) |ln| {
        var in_manifest = false;
        for (deps) |d| {
            if (std.mem.eql(u8, d.name, ln)) {
                in_manifest = true;
                break;
            }
        }
        if (!in_manifest) {
            try drifts.append(allocator, .{ .name = try allocator.dupe(u8, ln), .kind = .extra });
        }
    }

    return drifts.toOwnedSlice(allocator);
}

/// Regenerate `zaza.lock` from `build.zig.zon`. The manifest is authoritative:
/// the lock is rewritten to mirror its pinned dependencies exactly.
fn lockReconcile(allocator: std.mem.Allocator, zon_path: []const u8, lock_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const zon = try readFile(a, zon_path);
    const deps = try parseZonDependencies(a, zon);
    const text = try renderLock(a, deps);
    try writeFile(lock_path, text);

    const stdout = stdoutWriter();
    try stdout.print("wrote {s} ({d} dependencies)\n", .{ lock_path, deps.len });
}

/// Verify `zaza.lock` matches `build.zig.zon` without writing. Prints each
/// disagreement and fails when any exist, so CI can assert a reproducible tree.
fn lockCheck(allocator: std.mem.Allocator, zon_path: []const u8, lock_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const zon = try readFile(a, zon_path);
    const lock_data = readFile(a, lock_path) catch {
        const stderr = stderrWriter();
        try stderr.print("error: {s} not found. Run `zaza lock` to generate it.\n", .{lock_path});
        return error.LockMissing;
    };

    const drifts = try lockDrift(a, zon, lock_data);
    if (drifts.len == 0) {
        const deps = try parseZonDependencies(a, zon);
        const stdout = stdoutWriter();
        try stdout.print("{s} is in sync with {s} ({d} dependencies)\n", .{ lock_path, zon_path, deps.len });
        return;
    }

    const stderr = stderrWriter();
    try stderr.print("error: {s} is out of sync with {s} ({d} difference(s)):\n", .{ lock_path, zon_path, drifts.len });
    for (drifts) |d| {
        switch (d.kind) {
            .missing => try stderr.print("  - {s}: in the manifest, absent from the lock\n", .{d.name}),
            .extra => try stderr.print("  - {s}: in the lock, absent from the manifest\n", .{d.name}),
            .hash_mismatch => try stderr.print(
                "  - {s}: hash differs\n      manifest {s}\n      lock     {s}\n",
                .{ d.name, d.manifest_hash, d.locked_hash },
            ),
        }
    }
    try stderr.print(
        "remediation: run `zaza lock` to regenerate the lock from the manifest, then commit it.\n",
        .{},
    );
    return error.LockDrift;
}
