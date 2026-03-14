const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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
    const stderr = std.io.getStdErr().writer();
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

    const stdout = std.io.getStdOut().writer();
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
    var child = std.process.Child.init(&.{ "zig", "fetch", url }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();

    const stdout = child.stdout.?;
    const out = try stdout.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(out);
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }

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

    var out = std.ArrayList(u8).init(allocator);
    try out.appendSlice(zon[0..start]);
    try out.appendSlice(entry);
    try out.appendSlice(zon[start..]);
    return out.toOwnedSlice();
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
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const size = (try file.stat()).size;
    const buf = try allocator.alloc(u8, size);
    _ = try file.readAll(buf);
    return buf;
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn listPackages(allocator: std.mem.Allocator, registry_path: []const u8) !void {
    const registry = readFile(allocator, registry_path) catch {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("error: registry not found at {s}\n", .{registry_path});
        return error.RegistryNotFound;
    };
    defer allocator.free(registry);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, registry, .{});
    defer parsed.deinit();

    const packages = parsed.value.object.get("packages") orelse return error.InvalidRegistry;
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Available packages ({d}):\n", .{packages.object.count()});
    var it = packages.object.iterator();
    while (it.next()) |entry| {
        const version = if (entry.value_ptr.object.get("version")) |v| v.string else "?";
        try stdout.print("  {s:20} {s}\n", .{ entry.key_ptr.*, version });
    }
}

fn searchPackages(allocator: std.mem.Allocator, registry_path: []const u8, query: []const u8) !void {
    const registry = readFile(allocator, registry_path) catch {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("error: registry not found at {s}\n", .{registry_path});
        return error.RegistryNotFound;
    };
    defer allocator.free(registry);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, registry, .{});
    defer parsed.deinit();

    const packages = parsed.value.object.get("packages") orelse return error.InvalidRegistry;
    const stdout = std.io.getStdOut().writer();
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
        const stderr = std.io.getStdErr().writer();
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

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    try out.appendSlice(zon[0..line_start]);
    try out.appendSlice(zon[remove_end..]);
    try writeFile(zon_path, out.items);
    removeLockEntry(allocator, "zaza.lock", name) catch {};

    const stdout = std.io.getStdOut().writer();
    try stdout.print("removed {s}\n", .{name});
}

fn initProject(allocator: std.mem.Allocator, name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // Check if build.zig.zon already exists
    if (std.fs.cwd().access("build.zig.zon", .{})) |_| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("error: build.zig.zon already exists. Remove it first.\n", .{});
        return error.AlreadyExists;
    } else |_| {}

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
        \\        .optimize = optimize,
        \\        .target = target,
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
    if (std.fs.cwd().access("build.zig", .{})) |_| {
        try stdout.print("  (skipped build.zig — already exists)\n", .{});
    } else |_| {
        try writeFile("build.zig", build_zig);
    }

    // Create src/main.cpp
    try std.fs.cwd().makePath("src");
    const main_cpp =
        \\#include <iostream>
        \\
        \\int main() {
        \\    std::cout << "Hello from Zaza!\n";
        \\    return 0;
        \\}
        \\
    ;
    if (std.fs.cwd().access("src/main.cpp", .{})) |_| {
        try stdout.print("  (skipped src/main.cpp — already exists)\n", .{});
    } else |_| {
        try writeFile("src/main.cpp", main_cpp);
    }

    try stdout.print("initialized project '{s}'\n", .{name});
    try stdout.print("  build.zig.zon   created\n", .{});
    try stdout.print("  build.zig       created\n", .{});
    try stdout.print("  src/main.cpp    created\n", .{});
    try stdout.print("\nNext: zig build run\n", .{});
}

pub fn updateLock(allocator: std.mem.Allocator, path: []const u8, name: []const u8, url: []const u8, hash: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var lock_data: []u8 = &.{};
    if (std.fs.cwd().openFile(path, .{})) |file| {
        defer file.close();
        const size = (try file.stat()).size;
        lock_data = try arena_alloc.alloc(u8, size);
        _ = try file.readAll(lock_data);
    } else |_| {
        lock_data = try arena_alloc.dupe(u8, "{\n  \"packages\": {}\n}\n");
    }

    var parsed = try std.json.parseFromSlice(std.json.Value, arena_alloc, lock_data, .{});
    defer parsed.deinit();
    var root = parsed.value;
    if (root.object.getPtr("packages") == null) {
        try root.object.put("packages", .{ .object = std.json.ObjectMap.init(arena_alloc) });
    }
    const packages = root.object.getPtr("packages").?;

    var entry = std.json.Value{
        .object = std.json.ObjectMap.init(arena_alloc),
    };
    try entry.object.put("name", .{ .string = name });
    try entry.object.put("source", .{ .string = "registry" });
    try entry.object.put("url", .{ .string = url });
    try entry.object.put("hash", .{ .string = hash });
    try packages.object.put(name, entry);

    var out = std.ArrayList(u8).init(arena_alloc);
    defer out.deinit();
    try std.json.stringify(root, .{ .whitespace = .indent_2 }, out.writer());
    try out.append('\n');
    try writeFile(path, out.items);
}

pub fn removeLockEntry(allocator: std.mem.Allocator, path: []const u8, name: []const u8) !void {
    const cwd = std.fs.cwd();
    const file = cwd.openFile(path, .{}) catch return;
    defer file.close();

    const size = (try file.stat()).size;
    const lock_data = try allocator.alloc(u8, size);
    defer allocator.free(lock_data);
    _ = try file.readAll(lock_data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, lock_data, .{});
    defer parsed.deinit();
    const packages = parsed.value.object.getPtr("packages") orelse return;
    _ = packages.object.orderedRemove(name);

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    try std.json.stringify(parsed.value, .{ .whitespace = .indent_2 }, out.writer());
    try out.append('\n');
    try writeFile(path, out.items);
}

pub fn parseDependencyNames(allocator: std.mem.Allocator, zon: []const u8) ![][]const u8 {
    const dep_marker = ".dependencies = .{";
    const idx = std.mem.indexOf(u8, zon, dep_marker) orelse return allocator.alloc([]const u8, 0);
    const start = idx + dep_marker.len;
    const end = findMatchingBrace(zon, start) orelse return error.BadZonFormat;
    const dep_block = zon[start..end];

    var names = std.ArrayList([]const u8).init(allocator);
    var it = std.mem.tokenizeAny(u8, dep_block, "\n");
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r,");
        if (!std.mem.startsWith(u8, trimmed, ".")) continue;
        if (std.mem.indexOf(u8, trimmed, " = .{")) |eq_idx| {
            try names.append(try allocator.dupe(u8, trimmed[1..eq_idx]));
        }
    }
    return names.toOwnedSlice();
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

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Dependencies ({d}):\n", .{names.len});
    for (names) |name| {
        try stdout.print("  {s:20} {s}\n", .{ name, if (locked.contains(name)) "locked" else "unlocked" });
    }
}
