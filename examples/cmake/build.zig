const std = @import("std");
const zigcpp = @import("../../zigcpp.zig");
const builder = @import("../../builder.zig");

// Let's use fmt library as an example - it has a CMake build system
const fmt_repo = "fmtlib/fmt";
const fmt_version = "10.2.1";

pub fn build(
    b: *std.Build,
    step: *std.Build.Step,
    optimize: std.builtin.OptimizeMode,
) !void {
    // Build for all desktop platforms
    for (builder.Platform.desktop) |platform| {
        const target = platform.target();
        
        // Create a build step for fmt
        var fmt = zigcpp.Cpp.createWithOptions(b, 
            b.fmt("fmt-{s}", .{platform.name}), 
            .library, 
            target, 
            optimize
        );
        defer fmt.deinit();

        // Configure fmt build
        _ = fmt.standard("20")
            .addGithubDependency(fmt_repo)
            .define("CMAKE_BUILD=true")
            .addSource("deps/fmt/src/format.cc");  // Add fmt source file

        try fmt.build();

        // Create a simple executable that uses fmt
        var app = zigcpp.Cpp.createWithOptions(b,
            b.fmt("cmake-example-{s}", .{platform.name}),
            .executable,
            target,
            optimize
        );
        defer app.deinit();

        _ = app.standard("20")
            .addSources(&.{"examples/cmake/src/main.cpp"})
            .includes(&.{"deps/fmt/include"})
            .addArtifact(fmt.artifact);

        try app.build();
        step.dependOn(&b.addInstallArtifact(app.artifact, .{}).step);
    }
} 