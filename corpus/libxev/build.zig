const std = @import("std");
const zaza = @import("zaza").api;

// libxev's C static library + header are staged by ./fetch.sh (needs Zig 0.16).
const libxev_dir = "vendor/libxev";

// Zig 0.16 moved the filesystem under std.Io, so Dir.access takes the build
// graph's Io handle. Only the taken branch is analysed.
fn buildRootHas(b: *std.Build, sub_path: []const u8) bool {
    const r = if (comptime @hasDecl(std.fs, "cwd"))
        b.build_root.handle.access(sub_path, .{})
    else
        b.build_root.handle.access(b.graph.io, sub_path, .{});
    return if (r) |_| true else |_| false;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    if (!buildRootHas(b, libxev_dir ++ "/libxev.a")) {
        std.debug.print(
            \\error: libxev not staged under {s}.
            \\       run ./fetch.sh first (requires Zig 0.16 to build libxev).
            \\
        , .{libxev_dir});
        return error.UpstreamSourcesMissing;
    }

    // A downstream C consumer of libxev's C API, expressed as a Zaza target.
    // libxev's xev.h only compiles as C99, so this uses Zaza's c_std option to
    // build the translation unit as C instead of C++ (which is what made this a
    // finding before the option existed).
    var consumer = zaza.Target.executable(.{
        .name = "libxev_consumer",
        .description = "C consumer of libxev's C API, built as a Zaza C99 target",
        .source_files = &.{"src/main.c"},
        .public_include_dirs = &.{libxev_dir},
        .public_defines = &.{"_POSIX_C_SOURCE=199309L"},
        .c_std = "99",
        .configs = &.{.{ .mode = .Release }},
    });
    const consumer_compile = try consumer.buildWithTarget(b, target);
    // Link libxev's prebuilt C static library.
    consumer_compile.root_module.addObjectFile(b.path(libxev_dir ++ "/libxev.a"));

    b.installArtifact(consumer_compile);

    const run = b.addRunArtifact(consumer_compile);
    const run_step = b.step("run", "Build the libxev C consumer and run it");
    run_step.dependOn(&run.step);
}
