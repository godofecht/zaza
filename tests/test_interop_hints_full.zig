const std = @import("std");
const testing = std.testing;
const hints = @import("interop_hints");

test "cmake command returns cmake hint" {
    const result = hints.commandHint(&.{ "cmake", "-B", "build" });
    try testing.expect(result != null);
    try testing.expect(std.mem.indexOf(u8, result.?, "CMake") != null);
}

test "git command returns git hint" {
    const result = hints.commandHint(&.{ "git", "clone", "https://example.com/repo" });
    try testing.expect(result != null);
    try testing.expect(std.mem.indexOf(u8, result.?, "Git") != null);
}

test "python command returns python hint" {
    const result = hints.commandHint(&.{ "python3", "generate.py" });
    try testing.expect(result != null);
    try testing.expect(std.mem.indexOf(u8, result.?, "Python") != null);
}

test "python substring match works" {
    const result = hints.commandHint(&.{ "/usr/bin/python3.11", "script.py" });
    try testing.expect(result != null);
    try testing.expect(std.mem.indexOf(u8, result.?, "Python") != null);
}

test "unknown command returns null" {
    const result = hints.commandHint(&.{ "cargo", "build" });
    try testing.expect(result == null);
}

test "empty argv returns null" {
    const result = hints.commandHint(&.{});
    try testing.expect(result == null);
}

test "cmake in non-first position still matches" {
    const result = hints.commandHint(&.{ "sudo", "cmake", "--build", "." });
    try testing.expect(result != null);
    try testing.expect(std.mem.indexOf(u8, result.?, "CMake") != null);
}

test "git in non-first position still matches" {
    const result = hints.commandHint(&.{ "env", "GIT_SSH_COMMAND=ssh", "git", "fetch" });
    try testing.expect(result != null);
    try testing.expect(std.mem.indexOf(u8, result.?, "Git") != null);
}
