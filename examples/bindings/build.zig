const std = @import("std");
const zigcpp = @import("../../zigcpp.zig");
const builder = @import("../../builder.zig");

pub fn build(
    b: *std.Build,
    step: *std.Build.Step,
    optimize: std.builtin.OptimizeMode,
) !void {
    // Build for all desktop platforms
    for (builder.Platform.desktop) |platform| {
        const target = platform.target();
        
        // Build C++ library
        var lib = zigcpp.Cpp.createWithOptions(b, 
            b.fmt("calculator-{s}", .{platform.name}), 
            .library, 
            target, 
            optimize
        );
        defer lib.deinit();

        _ = lib.standard("20")
            .addSources(&.{
                "examples/bindings/src/calculator.cpp",
                "examples/bindings/src/calculator_wrapper.cpp",
            });
        try lib.build();

        // Build Zig executable
        const exe = b.addExecutable(.{
            .name = b.fmt("bindings-example-{s}", .{platform.name}),
            .root_source_file = .{ .path = "examples/bindings/zig/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.addIncludePath(.{ .path = "examples/bindings/src" });
        exe.linkLibrary(lib.artifact);
        exe.addModule("calculator", b.createModule(.{
            .source_file = .{ .path = "examples/bindings/zig/calculator.zig" },
        }));

        step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    }
} 