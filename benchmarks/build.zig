//! Standalone build file for the benchmark harness.
//!
//! Run from the repository root:
//!
//!     zig build --build-file benchmarks/build.zig bench
//!
//! It is kept out of the root build.zig on purpose. The harness spawns `zig`,
//! `cmake` and `ninja`, so it must never run as part of `zig build test`.

const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const step = b.step("bench", "Measure real build times for zaza and, where available, CMake");

    // The harness drives child processes through std.process.Child.run, which
    // 0.16 removed in favour of an explicit Io instance. Rather than carry a
    // second spelling of the whole harness, say so and stop. Nothing in the
    // main suite depends on this build file, so 0.16 support of the repo is
    // unaffected.
    if (comptime builtin.zig_version.order(.{ .major = 0, .minor = 16, .patch = 0 }) != .lt) {
        step.dependOn(&b.addFail(
            "benchmarks/build_bench.zig needs Zig 0.14.1 or 0.15.2. " ++
                "0.16 removed std.process.Child.run.",
        ).step);
        return;
    }

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "build_bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build_bench.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.stdio = .inherit;
    // 0.14.1 and 0.15.2 disagree about the working directory a run step
    // inherits, which breaks the relative path to the artifact. Pin it to the
    // directory `zig build` was invoked from.
    run.setCwd(.{ .cwd_relative = "." });
    // Measure the zig that is driving this build, and take build_lib from the
    // checkout this build file lives in. build_root is benchmarks/, so its
    // parent is the checkout. The harness resolves this against the same cwd.
    run.addArgs(&.{ "--zig", b.graph.zig_exe });
    run.addArgs(&.{ "--repo-root", b.pathFromRoot("..") });
    if (b.args) |extra| run.addArgs(extra);

    step.dependOn(&run.step);
}
