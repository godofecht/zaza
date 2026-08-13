//! A bounded generator-expression evaluator.
//!
//! CMake's generator expressions (`$<...>`) condition a value on the build
//! configuration and platform. Zaza does not evaluate the whole CMake grammar.
//! It evaluates the common conditional subset, enough to write config- and
//! platform-specific flags as data:
//!
//! - `$<CONFIG:Debug>`      -> "1" when the active config is Debug, else "0"
//! - `$<PLATFORM_ID:linux>` -> "1" when the platform matches, else "0"
//! - `$<BOOL:value>`        -> "1" when value is truthy, else "0"
//! - `$<NOT:cond>`          -> flips a 0/1
//! - `$<AND:a,b,...>`       -> "1" when every argument is "1"
//! - `$<OR:a,b,...>`        -> "1" when any argument is "1"
//! - `$<IF:cond,yes,no>`    -> yes when cond is "1", else no
//! - `$<cond:text>`         -> text when cond is "1", else "" (conditional include)
//!
//! Expressions nest. Anything outside a `$<...>` is copied through, so a plain
//! string with no generator expression evaluates to itself.

const std = @import("std");

/// The facts a generator expression is evaluated against.
pub const Context = struct {
    /// The active configuration name, e.g. "Debug" or "Release".
    config: []const u8 = "",
    /// The platform identifier, e.g. "linux", "macos", "windows".
    platform: []const u8 = "",
};

pub const Error = error{ UnbalancedExpression, UnknownExpression } || std.mem.Allocator.Error;

/// Evaluate `expr` against `ctx`. The result is owned by the caller.
pub fn eval(allocator: std.mem.Allocator, expr: []const u8, ctx: Context) Error![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < expr.len) {
        if (i + 1 < expr.len and expr[i] == '$' and expr[i + 1] == '<') {
            const end = matchClose(expr, i) orelse return error.UnbalancedExpression;
            const inner = expr[i + 2 .. end];
            const value = try evalNode(allocator, inner, ctx);
            defer allocator.free(value);
            try out.appendSlice(allocator, value);
            i = end + 1;
        } else {
            try out.append(allocator, expr[i]);
            i += 1;
        }
    }

    return out.toOwnedSlice(allocator);
}

/// True when `expr` evaluates to the truthy string "1".
pub fn evalBool(allocator: std.mem.Allocator, expr: []const u8, ctx: Context) Error!bool {
    const v = try eval(allocator, expr, ctx);
    defer allocator.free(v);
    return isTrue(v);
}

/// Evaluate the contents of one `$<...>` node (the text between the brackets).
fn evalNode(allocator: std.mem.Allocator, inner: []const u8, ctx: Context) Error![]const u8 {
    const colon = splitHead(inner);

    // `$<CONFIG:name>` and `$<PLATFORM_ID:id>` compare against the context.
    if (colon) |c| {
        const head = inner[0..c];
        const rest = inner[c + 1 ..];

        if (std.mem.eql(u8, head, "CONFIG")) {
            const arg = try eval(allocator, rest, ctx);
            defer allocator.free(arg);
            return boolString(allocator, std.ascii.eqlIgnoreCase(arg, ctx.config));
        }
        if (std.mem.eql(u8, head, "PLATFORM_ID")) {
            const arg = try eval(allocator, rest, ctx);
            defer allocator.free(arg);
            return boolString(allocator, std.ascii.eqlIgnoreCase(arg, ctx.platform));
        }
        if (std.mem.eql(u8, head, "BOOL")) {
            const arg = try eval(allocator, rest, ctx);
            defer allocator.free(arg);
            return boolString(allocator, isTrue(arg));
        }
        if (std.mem.eql(u8, head, "NOT")) {
            const arg = try eval(allocator, rest, ctx);
            defer allocator.free(arg);
            return boolString(allocator, !isTrue(arg));
        }
        if (std.mem.eql(u8, head, "AND")) {
            var all = true;
            var it = argIterator(rest);
            while (it.next()) |arg| {
                const v = try eval(allocator, arg, ctx);
                defer allocator.free(v);
                if (!isTrue(v)) all = false;
            }
            return boolString(allocator, all);
        }
        if (std.mem.eql(u8, head, "OR")) {
            var any = false;
            var it = argIterator(rest);
            while (it.next()) |arg| {
                const v = try eval(allocator, arg, ctx);
                defer allocator.free(v);
                if (isTrue(v)) any = true;
            }
            return boolString(allocator, any);
        }
        if (std.mem.eql(u8, head, "IF")) {
            var it = argIterator(rest);
            const cond_raw = it.next() orelse "";
            const yes = it.next() orelse "";
            const no = it.next() orelse "";
            const cond = try eval(allocator, cond_raw, ctx);
            defer allocator.free(cond);
            return eval(allocator, if (isTrue(cond)) yes else no, ctx);
        }

        // `$<cond:text>`: the head is itself an expression. Include the text
        // only when it evaluates true.
        const cond = try eval(allocator, head, ctx);
        defer allocator.free(cond);
        if (isTrue(cond)) {
            return eval(allocator, rest, ctx);
        }
        return allocator.dupe(u8, "");
    }

    // No colon: `$<1>` / `$<0>` are the bare booleans; anything else is a
    // literal passed through unchanged.
    if (std.mem.eql(u8, inner, "1") or std.mem.eql(u8, inner, "0")) {
        return allocator.dupe(u8, inner);
    }
    return eval(allocator, inner, ctx);
}

/// Index of the `>` that closes the `$<` at `start`. Handles nesting.
fn matchClose(expr: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var i = start;
    while (i < expr.len) : (i += 1) {
        if (i + 1 < expr.len and expr[i] == '$' and expr[i + 1] == '<') {
            depth += 1;
            i += 1;
        } else if (expr[i] == '>') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

/// The index of the first top-level `:` in a node's contents, or null when the
/// node has none. A `:` inside a nested `$<...>` does not count.
fn splitHead(inner: []const u8) ?usize {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < inner.len) : (i += 1) {
        if (i + 1 < inner.len and inner[i] == '$' and inner[i + 1] == '<') {
            depth += 1;
            i += 1;
        } else if (inner[i] == '>') {
            if (depth > 0) depth -= 1;
        } else if (inner[i] == ':' and depth == 0) {
            return i;
        }
    }
    return null;
}

/// Iterate the top-level comma-separated arguments of a node, ignoring commas
/// nested inside `$<...>`.
const ArgIterator = struct {
    text: []const u8,
    pos: usize = 0,

    fn next(self: *ArgIterator) ?[]const u8 {
        if (self.pos > self.text.len) return null;
        if (self.pos == self.text.len) {
            self.pos += 1;
            return self.text[self.text.len..];
        }
        var depth: usize = 0;
        var i = self.pos;
        while (i < self.text.len) : (i += 1) {
            if (i + 1 < self.text.len and self.text[i] == '$' and self.text[i + 1] == '<') {
                depth += 1;
                i += 1;
            } else if (self.text[i] == '>') {
                if (depth > 0) depth -= 1;
            } else if (self.text[i] == ',' and depth == 0) {
                const arg = self.text[self.pos..i];
                self.pos = i + 1;
                return arg;
            }
        }
        const arg = self.text[self.pos..];
        self.pos = self.text.len + 1;
        return arg;
    }
};

fn argIterator(text: []const u8) ArgIterator {
    return .{ .text = text };
}

/// CMake's truthiness: "1", "ON", "YES", "TRUE", "Y" (case-insensitive) and any
/// non-zero number are true; "0", "", "OFF", "NO", "FALSE", "N" are false.
fn isTrue(value: []const u8) bool {
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, "1")) return true;
    if (std.mem.eql(u8, value, "0")) return false;
    const truthy = [_][]const u8{ "on", "yes", "true", "y" };
    for (truthy) |t| {
        if (std.ascii.eqlIgnoreCase(value, t)) return true;
    }
    const falsy = [_][]const u8{ "off", "no", "false", "n" };
    for (falsy) |f| {
        if (std.ascii.eqlIgnoreCase(value, f)) return false;
    }
    // A non-zero number is true; anything else is false.
    const n = std.fmt.parseInt(i64, value, 10) catch return false;
    return n != 0;
}

fn boolString(allocator: std.mem.Allocator, value: bool) Error![]const u8 {
    return allocator.dupe(u8, if (value) "1" else "0");
}

test "plain text passes through" {
    const a = std.testing.allocator;
    const v = try eval(a, "-DFOO", .{});
    defer a.free(v);
    try std.testing.expectEqualStrings("-DFOO", v);
}

test "CONFIG compares against the context" {
    const a = std.testing.allocator;
    const debug = try eval(a, "$<CONFIG:Debug>", .{ .config = "Debug" });
    defer a.free(debug);
    try std.testing.expectEqualStrings("1", debug);

    const release = try eval(a, "$<CONFIG:Debug>", .{ .config = "Release" });
    defer a.free(release);
    try std.testing.expectEqualStrings("0", release);
}

test "conditional include emits text only when the condition holds" {
    const a = std.testing.allocator;
    const on = try eval(a, "$<$<CONFIG:Debug>:-DDBG>", .{ .config = "Debug" });
    defer a.free(on);
    try std.testing.expectEqualStrings("-DDBG", on);

    const off = try eval(a, "$<$<CONFIG:Debug>:-DDBG>", .{ .config = "Release" });
    defer a.free(off);
    try std.testing.expectEqualStrings("", off);
}

test "IF picks a branch" {
    const a = std.testing.allocator;
    const yes = try eval(a, "$<IF:$<CONFIG:Debug>,dbg,rel>", .{ .config = "Debug" });
    defer a.free(yes);
    try std.testing.expectEqualStrings("dbg", yes);

    const no = try eval(a, "$<IF:$<CONFIG:Debug>,dbg,rel>", .{ .config = "Release" });
    defer a.free(no);
    try std.testing.expectEqualStrings("rel", no);
}

test "boolean algebra: NOT, AND, OR" {
    const a = std.testing.allocator;
    const ctx = Context{ .config = "Debug", .platform = "linux" };

    const not = try eval(a, "$<NOT:$<CONFIG:Release>>", ctx);
    defer a.free(not);
    try std.testing.expectEqualStrings("1", not);

    const andv = try eval(a, "$<AND:$<CONFIG:Debug>,$<PLATFORM_ID:linux>>", ctx);
    defer a.free(andv);
    try std.testing.expectEqualStrings("1", andv);

    const orv = try eval(a, "$<OR:$<CONFIG:Release>,$<PLATFORM_ID:linux>>", ctx);
    defer a.free(orv);
    try std.testing.expectEqualStrings("1", orv);
}

test "BOOL applies CMake truthiness" {
    const a = std.testing.allocator;
    for ([_][]const u8{ "ON", "yes", "3" }) |t| {
        const expr = try std.fmt.allocPrint(a, "$<BOOL:{s}>", .{t});
        defer a.free(expr);
        const v = try eval(a, expr, .{});
        defer a.free(v);
        try std.testing.expectEqualStrings("1", v);
    }
    for ([_][]const u8{ "OFF", "no", "0", "" }) |f| {
        const expr = try std.fmt.allocPrint(a, "$<BOOL:{s}>", .{f});
        defer a.free(expr);
        const v = try eval(a, expr, .{});
        defer a.free(v);
        try std.testing.expectEqualStrings("0", v);
    }
}

test "unbalanced expression is an error" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.UnbalancedExpression, eval(a, "$<CONFIG:Debug", .{ .config = "Debug" }));
}
