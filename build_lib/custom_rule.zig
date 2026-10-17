//! Typed per-file generators backed by Zig's cached Run steps.
//! Unlike an untracked pre-build command, the input file is a declared build
//! dependency and its output is a LazyPath used directly by compilation.
//!
//! The deliberately small API models the per-source subset of CMake 4.5's
//! add_custom_rule(); it is not a full CMake file-set/configurator implementation.

const std = @import("std");

pub const Rule = struct {
    name: []const u8,
    /// Argument tokens. Exactly one <SOURCE> and <OUTPUT> are required.
    /// A <GENERATOR> token is allowed when generator_file is set, and makes
    /// edits to the generator script invalidate the cached action.
    argv: []const []const u8,
    generator_file: ?[]const u8 = null,
    /// A generated C or C++ source (e.g. ".cpp", ".c").
    output_suffix: []const u8 = ".cpp",

    pub fn validate(self: Rule) !void {
        if (self.name.len == 0 or self.argv.len == 0) return error.InvalidRule;
        if (self.output_suffix.len < 2 or self.output_suffix[0] != '.') return error.InvalidOutputSuffix;
        var sources: usize = 0;
        var outputs: usize = 0;
        var generators: usize = 0;
        for (self.argv) |arg| {
            if (std.mem.eql(u8, arg, "<SOURCE>")) sources += 1;
            if (std.mem.eql(u8, arg, "<OUTPUT>")) outputs += 1;
            if (std.mem.eql(u8, arg, "<GENERATOR>")) generators += 1;
        }
        if (sources != 1 or outputs != 1) return error.InvalidRulePlaceholders;
        if (generators != @as(usize, if (self.generator_file == null) 0 else 1)) return error.InvalidGeneratorPlaceholder;
        if (std.mem.eql(u8, self.argv[0], "<SOURCE>") or
            std.mem.eql(u8, self.argv[0], "<OUTPUT>") or
            std.mem.eql(u8, self.argv[0], "<GENERATOR>")) return error.InvalidRuleExecutable;
    }

    /// Reuse a rule with a different name and optional command/output shape.
    /// Original rule remains unchanged.
    pub fn derive(self: Rule, name: []const u8, argv: ?[]const []const u8, suffix: ?[]const u8) Rule {
        var result = self;
        result.name = name;
        if (argv) |v| result.argv = v;
        if (suffix) |v| result.output_suffix = v;
        return result;
    }

    pub fn outputFileName(self: Rule, allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
        try self.validate();
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ std.fs.path.stem(source), self.output_suffix });
    }

    /// Attach each generator output directly to the compile step. Each source
    /// gets an independent cacheable action, so editing one source re-runs only
    /// its own generator. Run's tracked file arguments supply build edges.
    pub fn addGeneratedSources(
        self: Rule,
        b: *std.Build,
        compile: *std.Build.Step.Compile,
        sources: []const []const u8,
        flags: []const []const u8,
    ) !void {
        try self.validate();
        for (sources) |source| {
            const output_name = try self.outputFileName(b.allocator, source);
            const run = b.addSystemCommand(&.{self.argv[0]});
            run.setName(b.fmt("{s}: {s}", .{ self.name, source }));
            var output: ?std.Build.LazyPath = null;
            for (self.argv[1..]) |arg| {
                if (std.mem.eql(u8, arg, "<SOURCE>")) {
                    run.addFileArg(b.path(source));
                } else if (std.mem.eql(u8, arg, "<GENERATOR>")) {
                    run.addFileArg(b.path(self.generator_file.?));
                } else if (std.mem.eql(u8, arg, "<OUTPUT>")) {
                    output = run.addOutputFileArg(output_name);
                } else {
                    run.addArg(arg);
                }
            }
            compile.root_module.addCSourceFile(.{ .file = output.?, .flags = flags });
        }
    }
};

/// A file set bound to a reusable template rule.
pub const Binding = struct {
    rule: Rule,
    files: []const []const u8,
};

test "template validation checks both tracked operands" {
    const valid = Rule{
        .name = "copy",
        .argv = &.{ "sh", "<GENERATOR>", "<SOURCE>", "<OUTPUT>" },
        .generator_file = "tools/generate.sh",
    };
    try valid.validate();
    try std.testing.expectError(error.InvalidRulePlaceholders, (Rule{
        .name = "broken",
        .argv = &.{ "tool", "<SOURCE>" },
    }).validate());
    try std.testing.expectError(error.InvalidGeneratorPlaceholder, (Rule{
        .name = "broken",
        .argv = &.{ "sh", "<GENERATOR>", "<SOURCE>", "<OUTPUT>" },
    }).validate());
}

test "derived rules inherit without modifying their base" {
    const base = Rule{
        .name = "transpile",
        .argv = &.{ "compiler", "<SOURCE>", "-o", "<OUTPUT>" },
    };
    const derived = base.derive("transpile_c", null, ".c");
    try std.testing.expectEqualStrings(".cpp", base.output_suffix);
    try std.testing.expectEqualStrings(".c", derived.output_suffix);
    const name = try derived.outputFileName(std.testing.allocator, "sources/widget.flow");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("widget.c", name);
}
