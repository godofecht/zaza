const std = @import("std");
const testing = std.testing;
const hints = @import("interop_hints");

test "command hints explain common external failures" {
    try testing.expectEqualStrings(
        "CMake command failed. Check generator availability, toolchain settings, and installed dependency metadata.",
        hints.commandHint(&.{"cmake", "--build", "build"}).?,
    );
    try testing.expectEqualStrings(
        "Git command failed. Check network access, repository URL, and credentials if the dependency is private.",
        hints.commandHint(&.{"git", "clone", "repo"}).?,
    );
    try testing.expectEqualStrings(
        "Python-based generation failed. Check that required Python modules for the dependency are installed.",
        hints.commandHint(&.{"python3", "script.py"}).?,
    );
}
