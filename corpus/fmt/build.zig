const std = @import("std");

// Zaza's public API, reached through the path dependency declared in
// build.zig.zon. This is the same surface a real downstream consumer imports.
const zaza = @import("zaza").api;

// Upstream fmt sources are fetched by ./fetch.sh into vendor/fmt (git-ignored),
// so this overlay carries only Zaza build files, not a vendored copy of fmt.
const fmt_src = "vendor/fmt/src";
const fmt_include = "vendor/fmt/include";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    // A guard that turns a missing checkout into an actionable message instead
    // of an opaque "file not found" from the compiler.
    b.build_root.handle.access(fmt_include, .{}) catch {
        std.debug.print(
            \\error: upstream fmt sources not found under {s}.
            \\       run ./fetch.sh first to check out the pinned fmt release.
            \\
        , .{fmt_include});
        return error.UpstreamSourcesMissing;
    };

    // The fmt compiled library, expressed as a Zaza static-library target.
    // This is the "target slice": fmt's two non-header translation units built
    // through Zaza's C/C++ graph layer rather than through fmt's CMakeLists.
    var fmt_lib = zaza.Target.staticLibrary(.{
        .name = "fmt",
        .description = "{fmt} formatting library, built as a Zaza C++ target slice",
        .source_files = &.{
            fmt_src ++ "/format.cc",
            fmt_src ++ "/os.cc",
        },
        .public_include_dirs = &.{fmt_include},
        .cpp_std = "17",
        .configs = &.{.{ .mode = .Release }},
    });
    const fmt_compile = try fmt_lib.buildWithTarget(b, target);

    // A small consumer executable that links the Zaza-built fmt slice. It is
    // the downstream proof: real fmt API calls compiled and linked against the
    // slice, then run.
    var consumer = zaza.Target.executable(.{
        .name = "fmt_consumer",
        .description = "Downstream consumer that links the Zaza-built fmt slice",
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{fmt_include},
        .cpp_std = "17",
        .configs = &.{.{ .mode = .Release }},
    });
    const consumer_compile = try consumer.buildWithTarget(b, target);
    consumer_compile.linkLibrary(fmt_compile);

    b.installArtifact(fmt_compile);
    b.installArtifact(consumer_compile);

    const run = b.addRunArtifact(consumer_compile);
    const run_step = b.step("run", "Build the fmt slice and run the consumer");
    run_step.dependOn(&run.step);
}
