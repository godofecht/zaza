const std = @import("std");

const ServerConfig = struct {
    root: []const u8,
    port: u16,
    max_requests: ?usize,
};

fn guessContentType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".js")) return "text/javascript; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".wasm")) return "application/wasm";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json; charset=utf-8";
    return "application/octet-stream";
}

fn trimRequestPath(path: []const u8) []const u8 {
    if (std.mem.eql(u8, path, "/")) return "index.html";
    return std.mem.trimLeft(u8, path, "/");
}

fn isSafePath(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "..") == null;
}

fn writeResponse(
    stream: std.net.Stream,
    status: []const u8,
    content_type: []const u8,
    body: []const u8,
    head_only: bool,
) !void {
    var writer = stream.writer();
    try writer.print(
        "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, content_type, body.len },
    );
    if (!head_only) {
        try writer.writeAll(body);
    }
}

fn handleConnection(allocator: std.mem.Allocator, root: []const u8, stream: std.net.Stream) !void {
    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();

    var buf: [1024]u8 = undefined;
    while (request.items.len < 4096) {
        const n = try stream.read(&buf);
        if (n == 0) break;
        try request.appendSlice(buf[0..n]);
        if (std.mem.indexOf(u8, request.items, "\r\n\r\n") != null) break;
    }

    if (request.items.len == 0) return;

    const line_end = std.mem.indexOf(u8, request.items, "\r\n") orelse return;
    const line = request.items[0..line_end];

    var parts = std.mem.splitScalar(u8, line, ' ');
    const method = parts.next() orelse return;
    const raw_path = parts.next() orelse return;

    const head_only = std.mem.eql(u8, method, "HEAD");
    if (!head_only and !std.mem.eql(u8, method, "GET")) {
        try writeResponse(stream, "405 Method Not Allowed", "text/plain; charset=utf-8", "method not allowed\n", false);
        return;
    }

    const relative_path = trimRequestPath(raw_path);
    if (!isSafePath(relative_path)) {
        try writeResponse(stream, "400 Bad Request", "text/plain; charset=utf-8", "bad path\n", head_only);
        return;
    }

    const full_path = try std.fs.path.join(allocator, &.{ root, relative_path });
    defer allocator.free(full_path);

    const body = std.fs.cwd().readFileAlloc(allocator, full_path, 4 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            try writeResponse(stream, "404 Not Found", "text/plain; charset=utf-8", "not found\n", head_only);
            return;
        },
        else => return err,
    };
    defer allocator.free(body);

    try writeResponse(stream, "200 OK", guessContentType(relative_path), body, head_only);
}

fn serve(config: ServerConfig) !void {
    const address = try std.net.Address.parseIp("127.0.0.1", config.port);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print("Serving {s} at http://127.0.0.1:{d}\n", .{ config.root, config.port });

    var served: usize = 0;
    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        try handleConnection(arena.allocator(), config.root, conn.stream);
        served += 1;

        if (config.max_requests) |limit| {
            if (served >= limit) break;
        }
    }
}

fn requestHead(allocator: std.mem.Allocator, port: u16, path: []const u8) !void {
    const address = try std.net.Address.parseIp("127.0.0.1", port);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    try stream.writer().print(
        "HEAD {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
        .{path},
    );

    var response = std.ArrayList(u8).init(allocator);
    defer response.deinit();

    var reader = stream.reader();
    var buf: [1024]u8 = undefined;
    while (true) {
        const n = try reader.read(&buf);
        if (n == 0) break;
        try response.appendSlice(buf[0..n]);
    }

    if (std.mem.indexOf(u8, response.items, " 200 ") == null) {
        std.debug.print("request failed for {s}\n{s}\n", .{ path, response.items });
        return error.BadHttpStatus;
    }
}

fn smoke(root: []const u8, port: u16, paths: []const []const u8) !void {
    const config = ServerConfig{
        .root = root,
        .port = port,
        .max_requests = paths.len + 1,
    };

    const thread = try std.Thread.spawn(.{}, serve, .{config});
    defer thread.join();

    var ready = false;
    var attempt: usize = 0;
    while (attempt < 20) : (attempt += 1) {
        requestHead(std.heap.page_allocator, port, paths[0]) catch {
            std.time.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        ready = true;
        break;
    }

    if (!ready) return error.ServerDidNotStart;

    for (paths) |path| {
        try requestHead(std.heap.page_allocator, port, path);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        std.debug.print("usage: {s} <serve|smoke> <root> <port> [paths...]\n", .{args[0]});
        return error.InvalidArguments;
    }

    const mode = args[1];
    const root = args[2];
    const port = try std.fmt.parseInt(u16, args[3], 10);

    if (std.mem.eql(u8, mode, "serve")) {
        try serve(.{
            .root = root,
            .port = port,
            .max_requests = null,
        });
        return;
    }

    if (std.mem.eql(u8, mode, "smoke")) {
        const default_paths = [_][]const u8{ "/index.html", "/app.js", "/wasm_exports_demo.wasm" };
        const paths = if (args.len > 4) args[4..] else default_paths[0..];
        try smoke(root, port, paths);
        return;
    }

    return error.InvalidArguments;
}
