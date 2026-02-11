const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) return usage();

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "fetch")) {
        if (args.len < 3) return usage();
        const name = args[2];
        const zon_path = "build.zig.zon";
        const registry_path = "registry/registry.json";
        try fetchIntoZon(allocator, registry_path, zon_path, name);
        return;
    }

    return usage();
}

fn usage() !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.print(
        "Usage:\n  vex fetch <name>\n",
        .{},
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

    var zon = try readFile(allocator, zon_path);
    defer allocator.free(zon);

    const updated = try upsertDependency(allocator, zon, name, url, hash);
    defer allocator.free(updated);

    try writeFile(zon_path, updated);
    try updateLock(allocator, "vex.lock", name, url, hash);

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
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }

    const trimmed = std.mem.trim(u8, out, " \t\r\n");
    return allocator.dupe(u8, trimmed);
}

fn upsertDependency(
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

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const size = (try file.stat()).size;
    const buf = try allocator.alloc(u8, size);
    _ = try file.readAll(buf);
    return buf;
}

fn writeFile(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn updateLock(allocator: std.mem.Allocator, path: []const u8, name: []const u8, url: []const u8, hash: []const u8) !void {
    var lock_data: []u8 = &.{};
    if (std.fs.cwd().openFile(path, .{})) |file| {
        defer file.close();
        const size = (try file.stat()).size;
        lock_data = try allocator.alloc(u8, size);
        _ = try file.readAll(lock_data);
    } else |_| {
        lock_data = try allocator.dupe(u8, "{\n  \"packages\": {}\n}\n");
    }
    defer allocator.free(lock_data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, lock_data, .{});
    defer parsed.deinit();
    var root = parsed.value;
    if (root.object.getPtr("packages") == null) {
        try root.object.put("packages", .{ .object = std.json.ObjectMap.init(allocator) });
    }
    const packages = root.object.getPtr("packages").?;

    var entry = std.json.Value{
        .object = std.json.ObjectMap.init(allocator),
    };
    try entry.object.put("url", .{ .string = url });
    try entry.object.put("hash", .{ .string = hash });
    try packages.object.put(name, entry);

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    try std.json.stringify(root, .{ .whitespace = .indent_2 }, out.writer());
    try out.append('\n');
    try writeFile(path, out.items);
}
