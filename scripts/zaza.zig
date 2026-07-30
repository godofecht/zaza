const std = @import("std");

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

    if (std.mem.eql(u8, cmd, "clean-deps") or std.mem.eql(u8, cmd, "clean")) {
        try cleanDeps(allocator);
        return;
    }

    if (std.mem.eql(u8, cmd, "cache")) {
        try cacheInfo(env, allocator);
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
        \\  zaza clean-deps      Remove deps/ and zig-out/deps (alias: clean)
        \\  zaza cache           Show the Zig cache directories and whether they are writable
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
