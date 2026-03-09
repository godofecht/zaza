const std = @import("std");

pub fn commandHint(argv: []const []const u8) ?[]const u8 {
    if (argv.len == 0) return null;
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "cmake")) {
            return "CMake command failed. Check generator availability, toolchain settings, and installed dependency metadata.";
        }
        if (std.mem.eql(u8, arg, "git")) {
            return "Git command failed. Check network access, repository URL, and credentials if the dependency is private.";
        }
        if (std.mem.indexOf(u8, arg, "python") != null) {
            return "Python-based generation failed. Check that required Python modules for the dependency are installed.";
        }
    }
    return null;
}
