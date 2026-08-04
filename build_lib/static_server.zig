const std = @import("std");
const builtin = @import("builtin");

// Zig 0.16 moved the filesystem and networking under std.Io and reworked the
// entry point. std.net, std.fs.cwd, and std.process.argsAlloc are all gone. The
// networking-heavy functions have a legacy path (0.14 / 0.15) and a 0.16 path,
// selected at comptime; only the taken branch is analysed. The HTTP parsing and
// content-type helpers are version-independent and shared.
//
// Two things that bite on 0.16 and are handled here: blocking socket calls only
// make progress inside an `io.concurrent` task (not on the bare main thread), so
// both the server and the client run as tasks; and `Reader.readSliceShort`
// blocks until its whole buffer fills, so reads use `readVec` for one chunk.
const on_016 = !@hasDecl(std, "net");

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
    // 0.16 renamed mem.trimLeft to mem.trimStart.
    if (comptime on_016) return std.mem.trimStart(u8, path, "/");
    return std.mem.trimLeft(u8, path, "/");
}

fn isSafePath(path: []const u8) bool {
    return std.mem.indexOf(u8, path, "..") == null;
}

fn formatHead(buf: []u8, status: []const u8, content_type: []const u8, len: usize) ![]u8 {
    return std.fmt.bufPrint(
        buf,
        "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, content_type, len },
    );
}

fn readBody(io: anytype, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (comptime on_016) {
        return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    } else {
        return std.fs.cwd().readFileAlloc(allocator, path, 4 * 1024 * 1024);
    }
}

const RequestLine = struct { method: []const u8, raw_path: []const u8 };

fn parseRequestLine(bytes: []const u8) ?RequestLine {
    const line_end = std.mem.indexOf(u8, bytes, "\r\n") orelse return null;
    const line = bytes[0..line_end];
    var parts = std.mem.splitScalar(u8, line, ' ');
    const method = parts.next() orelse return null;
    const raw_path = parts.next() orelse return null;
    return .{ .method = method, .raw_path = raw_path };
}

// --- legacy networking (Zig 0.14 / 0.15) -----------------------------------

const legacy = struct {
    fn writeResponse(
        stream: std.net.Stream,
        status: []const u8,
        content_type: []const u8,
        body: []const u8,
        head_only: bool,
    ) !void {
        var header_buf: [1024]u8 = undefined;
        const header = try formatHead(&header_buf, status, content_type, body.len);
        try stream.writeAll(header);
        if (!head_only) try stream.writeAll(body);
    }

    fn handleConnection(allocator: std.mem.Allocator, root: []const u8, stream: std.net.Stream) !void {
        var request: std.ArrayListUnmanaged(u8) = .empty;
        defer request.deinit(allocator);

        var buf: [1024]u8 = undefined;
        while (request.items.len < 4096) {
            const n = try stream.read(&buf);
            if (n == 0) break;
            try request.appendSlice(allocator, buf[0..n]);
            if (std.mem.indexOf(u8, request.items, "\r\n\r\n") != null) break;
        }
        if (request.items.len == 0) return;

        const line = parseRequestLine(request.items) orelse return;
        const head_only = std.mem.eql(u8, line.method, "HEAD");
        if (!head_only and !std.mem.eql(u8, line.method, "GET")) {
            try writeResponse(stream, "405 Method Not Allowed", "text/plain; charset=utf-8", "method not allowed\n", false);
            return;
        }

        const relative_path = trimRequestPath(line.raw_path);
        if (!isSafePath(relative_path)) {
            try writeResponse(stream, "400 Bad Request", "text/plain; charset=utf-8", "bad path\n", head_only);
            return;
        }

        const full_path = try std.fs.path.join(allocator, &.{ root, relative_path });
        defer allocator.free(full_path);

        const body = readBody({}, allocator, full_path) catch |err| switch (err) {
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

        var request_buf: [1024]u8 = undefined;
        const request = try std.fmt.bufPrint(
            &request_buf,
            "HEAD {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
            .{path},
        );
        try stream.writeAll(request);

        var response: std.ArrayListUnmanaged(u8) = .empty;
        defer response.deinit(allocator);

        var buf: [1024]u8 = undefined;
        while (true) {
            const n = try stream.read(&buf);
            if (n == 0) break;
            try response.appendSlice(allocator, buf[0..n]);
        }

        if (std.mem.indexOf(u8, response.items, " 200 ") == null) {
            std.debug.print("request failed for {s}\n{s}\n", .{ path, response.items });
            return error.BadHttpStatus;
        }
    }
};

// --- Zig 0.16 networking (std.Io.net) --------------------------------------

const io16 = struct {
    // One chunk from the stream, or 0 at end. Reader.readSliceShort blocks until
    // the whole buffer fills; readVec returns what one read yields.
    fn readSome(r: *std.Io.Reader, buf: []u8) !usize {
        var data: [1][]u8 = .{buf};
        return r.readVec(&data) catch |err| switch (err) {
            error.EndOfStream => @as(usize, 0),
            else => err,
        };
    }

    fn writeResponse(
        io: std.Io,
        stream: std.Io.net.Stream,
        status: []const u8,
        content_type: []const u8,
        body: []const u8,
        head_only: bool,
    ) !void {
        var header_buf: [1024]u8 = undefined;
        const header = try formatHead(&header_buf, status, content_type, body.len);
        var wbuf: [4096]u8 = undefined;
        var w = stream.writer(io, &wbuf);
        try w.interface.writeAll(header);
        if (!head_only) try w.interface.writeAll(body);
        try w.interface.flush();
    }

    fn handleConnection(io: std.Io, allocator: std.mem.Allocator, root: []const u8, stream: std.Io.net.Stream) !void {
        var request: std.ArrayListUnmanaged(u8) = .empty;
        defer request.deinit(allocator);

        var rbuf: [4096]u8 = undefined;
        var r = stream.reader(io, &rbuf);
        var buf: [1024]u8 = undefined;
        while (request.items.len < 4096) {
            const n = try readSome(&r.interface, &buf);
            if (n == 0) break;
            try request.appendSlice(allocator, buf[0..n]);
            if (std.mem.indexOf(u8, request.items, "\r\n\r\n") != null) break;
        }
        if (request.items.len == 0) return;

        const line = parseRequestLine(request.items) orelse return;
        const head_only = std.mem.eql(u8, line.method, "HEAD");
        if (!head_only and !std.mem.eql(u8, line.method, "GET")) {
            try writeResponse(io, stream, "405 Method Not Allowed", "text/plain; charset=utf-8", "method not allowed\n", false);
            return;
        }

        const relative_path = trimRequestPath(line.raw_path);
        if (!isSafePath(relative_path)) {
            try writeResponse(io, stream, "400 Bad Request", "text/plain; charset=utf-8", "bad path\n", head_only);
            return;
        }

        const full_path = try std.fs.path.join(allocator, &.{ root, relative_path });
        defer allocator.free(full_path);

        const body = readBody(io, allocator, full_path) catch |err| switch (err) {
            error.FileNotFound => {
                try writeResponse(io, stream, "404 Not Found", "text/plain; charset=utf-8", "not found\n", head_only);
                return;
            },
            else => return err,
        };
        defer allocator.free(body);

        try writeResponse(io, stream, "200 OK", guessContentType(relative_path), body, head_only);
    }

    fn serve(io: std.Io, config: ServerConfig) !void {
        var address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", config.port);
        var server = try address.listen(io, .{ .reuse_address = true });
        defer server.deinit(io);

        std.debug.print("Serving {s} at http://127.0.0.1:{d}\n", .{ config.root, config.port });

        var served: usize = 0;
        while (true) {
            var stream = try server.accept(io);
            defer stream.close(io);

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();

            try handleConnection(io, arena.allocator(), config.root, stream);
            served += 1;

            if (config.max_requests) |limit| {
                if (served >= limit) break;
            }
        }
    }

    fn requestHead(io: std.Io, allocator: std.mem.Allocator, port: u16, path: []const u8) !void {
        var address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", port);
        var stream = try address.connect(io, .{ .mode = .stream });
        defer stream.close(io);

        var request_buf: [1024]u8 = undefined;
        const request = try std.fmt.bufPrint(
            &request_buf,
            "HEAD {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n",
            .{path},
        );
        var wbuf: [1024]u8 = undefined;
        var w = stream.writer(io, &wbuf);
        try w.interface.writeAll(request);
        try w.interface.flush();

        var response: std.ArrayListUnmanaged(u8) = .empty;
        defer response.deinit(allocator);

        var rbuf: [1024]u8 = undefined;
        var r = stream.reader(io, &rbuf);
        var buf: [1024]u8 = undefined;
        while (true) {
            const n = try readSome(&r.interface, &buf);
            if (n == 0) break;
            try response.appendSlice(allocator, buf[0..n]);
        }

        if (std.mem.indexOf(u8, response.items, " 200 ") == null) {
            std.debug.print("request failed for {s}\n{s}\n", .{ path, response.items });
            return error.BadHttpStatus;
        }
    }

    // The client half of the smoke test, run as its own task: wait for the
    // server to come up, then request each path.
    fn runClient(io: std.Io, port: u16, paths: []const []const u8) !void {
        var ready = false;
        var attempt: usize = 0;
        while (attempt < 20) : (attempt += 1) {
            requestHead(io, std.heap.page_allocator, port, paths[0]) catch {
                std.Io.sleep(io, std.Io.Duration.fromNanoseconds(100 * std.time.ns_per_ms), .awake) catch {};
                continue;
            };
            ready = true;
            break;
        }
        if (!ready) return error.ServerDidNotStart;

        for (paths) |path| {
            try requestHead(io, std.heap.page_allocator, port, path);
        }
    }
};

// The active implementation for this Zig version.
const impl = if (on_016) io16 else legacy;

// `await` is a keyword on 0.14 / 0.15, so the Future.await method cannot be
// spelled with dot syntax in source those parsers see, even in a branch they do
// not analyse. Reach it through @field, which parses everywhere and is only
// analysed on 0.16. Returns the task's result so the caller can propagate it.
fn awaitFuture(future: anytype, io: std.Io) anyerror!void {
    return @field(@TypeOf(future.*), "await")(future, io);
}

fn smoke(root: []const u8, port: u16, paths: []const []const u8) !void {
    if (comptime on_016) return smoke016(root, port, paths);
    return smokeLegacy(root, port, paths);
}

// 0.14 / 0.15: the server runs on a std.Thread; the client runs on the main
// thread. Blocking socket calls are ordinary blocking syscalls here.
fn smokeLegacy(root: []const u8, port: u16, paths: []const []const u8) !void {
    const config = ServerConfig{ .root = root, .port = port, .max_requests = paths.len + 1 };

    const thread = try std.Thread.spawn(.{}, legacy.serve, .{config});
    defer thread.join();

    var ready = false;
    var attempt: usize = 0;
    while (attempt < 20) : (attempt += 1) {
        legacy.requestHead(std.heap.page_allocator, port, paths[0]) catch {
            std.Thread.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        ready = true;
        break;
    }
    if (!ready) return error.ServerDidNotStart;

    for (paths) |path| {
        try legacy.requestHead(std.heap.page_allocator, port, path);
    }
}

// 0.16: blocking I/O only progresses inside a task, so both the server and the
// client run via io.concurrent on the shared threaded Io. Once listen succeeds
// the server serves exactly max_requests and returns, so awaiting it cannot
// hang even when the client fails partway.
fn smoke016(root: []const u8, port: u16, paths: []const []const u8) !void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const config = ServerConfig{ .root = root, .port = port, .max_requests = paths.len + 1 };
    var server = try io.concurrent(io16.serve, .{ io, config });
    var client = try io.concurrent(io16.runClient, .{ io, port, paths });

    awaitFuture(&client, io) catch |err| {
        awaitFuture(&server, io) catch {};
        return err;
    };
    awaitFuture(&server, io) catch {};
}

// --- entry point -----------------------------------------------------------

pub const main = if (on_016) main016 else mainLegacy;

fn mainLegacy() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    return run(args);
}

fn main016(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const args = try init.args.toSlice(arena.allocator());
    return run(args);
}

fn run(args: []const [:0]const u8) !void {
    if (args.len < 4) {
        std.debug.print("usage: {s} <serve|smoke> <root> <port> [paths...]\n", .{args[0]});
        return error.InvalidArguments;
    }

    const mode = args[1];
    const root = args[2];
    const port = try std.fmt.parseInt(u16, args[3], 10);

    if (std.mem.eql(u8, mode, "serve")) {
        const config = ServerConfig{ .root = root, .port = port, .max_requests = null };
        if (comptime on_016) {
            var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
            defer threaded.deinit();
            const io = threaded.io();
            var task = try io.concurrent(io16.serve, .{ io, config });
            return awaitFuture(&task, io);
        } else {
            try legacy.serve(config);
        }
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
