const std = @import("std");
const cpp = @import("cpp_example.zig");

const Port = 3000;

fn getString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| s,
        else => error.ExpectedString,
    };
}

fn getArray(value: std.json.Value) ![]const std.json.Value {
    return switch (value) {
        .array => |a| a.items,
        else => error.ExpectedArray,
    };
}

fn getObject(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |o| o,
        else => error.ExpectedObject,
    };
}

fn dupeStringArray(allocator: std.mem.Allocator, array: []const std.json.Value) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, array.len);
    errdefer {
        for (result) |item| {
            allocator.free(item);
        }
        allocator.free(result);
    }
    
    for (array, 0..) |item, i| {
        result[i] = try allocator.dupe(u8, try getString(item));
    }
    return result;
}

fn dupeDeps(allocator: std.mem.Allocator, array: []const std.json.Value) ![]const cpp.Dependency {
    const result = try allocator.alloc(cpp.Dependency, array.len);
    errdefer {
        for (result) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.url);
            if (dep.include_path) |path| {
                if (path.len > 0) allocator.free(path);
            }
            if (dep.build_command.len > 0) {
                for (dep.build_command) |cmd| {
                    allocator.free(cmd);
                }
                allocator.free(dep.build_command);
            }
        }
        allocator.free(result);
    }
    
    for (array, 0..) |dep_val, i| {
        const dep = try getObject(dep_val);
        result[i] = .{
            .name = try allocator.dupe(u8, try getString(dep.get("name").?)),
            .url = try allocator.dupe(u8, try getString(dep.get("url").?)),
            .include_path = if (dep.get("include_path")) |path| 
                if (path == .null) null 
                else try allocator.dupe(u8, try getString(path)) 
            else null,
            .type = if (dep.get("type")) |t| 
                if (t == .null) null 
                else if (std.mem.eql(u8, try getString(t), "Zig")) .Zig 
                else .CMake 
            else null,
            .build_command = &.{},
        };
    }
    return result;
}

fn jsonToCppExample(allocator: std.mem.Allocator, value: std.json.Value) !cpp.CppExample {
    const root = try getObject(value);
    return cpp.CppExample{
        .name = try allocator.dupe(u8, try getString(root.get("name").?)),
        .description = try allocator.dupe(u8, try getString(root.get("description").?)),
        .source_files = try dupeStringArray(allocator, try getArray(root.get("source_files").?)),
        .include_dirs = try dupeStringArray(allocator, try getArray(root.get("include_dirs").?)),
        .cpp_flags = try dupeStringArray(allocator, try getArray(root.get("cpp_flags").?)),
        .deps = try dupeDeps(allocator, try getArray(root.get("deps").?)),
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = if (std.mem.eql(u8, try getString(root.get("deps_build_system").?), "Zig")) .Zig else .CMake,
        .main_build_system = if (std.mem.eql(u8, try getString(root.get("main_build_system").?), "Zig")) .Zig else .CMake,
        .cpp_std = try allocator.dupe(u8, try getString(root.get("cpp_std").?)),
    };
}

fn saveConfig(allocator: std.mem.Allocator, json_str: []const u8) !void {
    var tree = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer tree.deinit();

    const root = try getObject(tree.value);
    
    // Generate the new build.zig content
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try buf.writer().writeAll(
        \\const std = @import("std");
        \\const cpp = @import("build_lib/cpp_example.zig");
        \\
        \\pub const example = cpp.CppExample{
        \\
    );

    // Write name and description
    try buf.writer().print("    .name = \"{s}\",\n", .{try getString(root.get("name").?)});
    try buf.writer().print("    .description = \"{s}\",\n", .{try getString(root.get("description").?)});

    // Write source files
    try buf.writer().writeAll("    .source_files = &.{");
    for (try getArray(root.get("source_files").?)) |src| {
        try buf.writer().print("\"{s}\",", .{try getString(src)});
    }
    try buf.writer().writeAll("},\n");

    // Write include dirs
    try buf.writer().writeAll("    .include_dirs = &.{");
    for (try getArray(root.get("include_dirs").?)) |dir| {
        try buf.writer().print("\"{s}\",", .{try getString(dir)});
    }
    try buf.writer().writeAll("},\n");

    // Write cpp flags
    try buf.writer().writeAll("    .cpp_flags = &.{");
    for (try getArray(root.get("cpp_flags").?)) |flag| {
        try buf.writer().print("\"{s}\",", .{try getString(flag)});
    }
    try buf.writer().writeAll("},\n");

    // Write dependencies
    try buf.writer().writeAll("    .deps = &.{\n");
    for (try getArray(root.get("dependencies").?)) |dep_val| {
        const dep = try getObject(dep_val);
        try buf.writer().print("        .{{ .name = \"{s}\", .url = \"{s}\", .type = .{s} }},\n", 
            .{
                try getString(dep.get("name").?),
                try getString(dep.get("url").?),
                try getString(dep.get("build_system").?),
            });
    }
    try buf.writer().writeAll("    },\n");

    // Write build systems
    try buf.writer().print("    .deps_build_system = .{s},\n", .{try getString(root.get("deps_build_system").?)});
    try buf.writer().print("    .main_build_system = .{s},\n", .{try getString(root.get("main_build_system").?)});

    // Write C++ standard
    try buf.writer().print("    .cpp_std = \"{s}\",\n", .{try getString(root.get("cpp_std").?)});

    // Close the struct
    try buf.writer().writeAll("};\n\n");

    // Add the build function
    try buf.writer().writeAll(
        \\pub fn build(b: *std.Build) !void {
        \\    const exe = try example.build(b);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    const run_step = b.step("run", "Run the example");
        \\    run_step.dependOn(&run_cmd.step);
        \\}
        \\
    );

    // Write the new build.zig
    try std.fs.cwd().writeFile(.{ .sub_path = "build.zig", .data = buf.items });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <json>\n", .{args[0]});
        return error.InvalidArguments;
    }

    var tree = try std.json.parseFromSlice(std.json.Value, allocator, args[1], .{});
    defer tree.deinit();

    const example = try jsonToCppExample(allocator, tree.value);
    defer example.deinit(allocator);

    // Start HTTP server
    const address = try std.net.Address.parseIp("127.0.0.1", Port);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print("\nServer running at http://localhost:{d}\n", .{Port});

    // Open browser using spawnProcess instead of Child.run
    const open_cmd = if (@import("builtin").target.os.tag == .windows)
        &[_][]const u8{ "cmd", "/C", "start", "http://localhost:3000" }
    else
        &[_][]const u8{ "xdg-open", "http://localhost:3000" };
    
    var proc = std.process.Child.init(open_cmd, allocator);
    _ = try proc.spawnAndWait();

    while (true) {
        const conn = try server.accept();
        defer conn.stream.close();

        var buf: [4096]u8 = undefined;
        const n = try conn.stream.read(&buf);
        const request = buf[0..n];

        if (std.mem.indexOf(u8, request, "POST /save") != null) {
            // Find the JSON payload
            if (std.mem.indexOf(u8, request, "\r\n\r\n")) |i| {
                const json = request[i + 4..];
                try saveConfig(allocator, json);
                
                // Send success response
                const response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}";
                _ = try conn.stream.write(response);
            }
        } else {
            // Serve the HTML page
            const response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n";
            _ = try conn.stream.write(response);
            try @import("build_viewer.zig").viewBuildConfig(example, conn.stream.writer());
        }
    }
} 