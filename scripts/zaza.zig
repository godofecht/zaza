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

    try run(allocator, args);
}

fn main016(init: std.process.Init.Minimal) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const args = try init.args.toSlice(arena.allocator());

    try run(allocator, args);
}

fn run(allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
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
        \\  zaza deps            List dependencies from build.zig.zon and lockfile state
        \\  zaza search <query>  Search packages by name
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
        const version = if (entry.value_ptr.object.get("version")) |v| v.string else "?";
        try stdout.print("  {s:20} {s}\n", .{ entry.key_ptr.*, version });
    }
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
    const stdout = stdoutWriter();
    var found: usize = 0;
    var it = packages.object.iterator();
    while (it.next()) |entry| {
        if (std.ascii.indexOfIgnoreCase(entry.key_ptr.*, query) != null) {
            const version = if (entry.value_ptr.object.get("version")) |v| v.string else "?";
            try stdout.print("  {s:20} {s}\n", .{ entry.key_ptr.*, version });
            found += 1;
        }
    }
    if (found == 0) {
        try stdout.print("No packages matching '{s}'\n", .{query});
    }
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

pub fn listCurrentDependencies(allocator: std.mem.Allocator, zon_path: []const u8, lock_path: []const u8) !void {
    const zon = try readFile(allocator, zon_path);
    defer allocator.free(zon);
    const names = try parseDependencyNames(allocator, zon);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }

    var locked = std.StringHashMap(void).init(allocator);
    defer locked.deinit();
    if (readFile(allocator, lock_path)) |lock_data| {
        defer allocator.free(lock_data);
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, lock_data, .{});
        defer parsed.deinit();
        if (parsed.value.object.get("packages")) |packages| {
            var it = packages.object.iterator();
            while (it.next()) |entry| {
                try locked.put(entry.key_ptr.*, {});
            }
        }
    } else |_| {}

    const stdout = stdoutWriter();
    try stdout.print("Dependencies ({d}):\n", .{names.len});
    for (names) |name| {
        try stdout.print("  {s:20} {s}\n", .{ name, if (locked.contains(name)) "locked" else "unlocked" });
    }
}
