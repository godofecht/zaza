//! A benchmark target declared through the first-class benchmark API.
//!
//! `test_suite.addBench` builds the executable in release, keeps it off the top
//! `test` step (a benchmark measures, it does not assert), inherits stdio so the
//! timings reach the terminal, and forwards `zig build bench-suite-run -- --reps
//! 9` to the process. The release build comes from the CppExample config, the
//! same way the rest of Zaza chooses optimize mode.

const std = @import("std");
const cpp = @import("../../build_lib/cpp_example.zig");
const test_suite = @import("../../build_lib/test_suite.zig");

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const bench = cpp.CppExample.executable(.{
        .name = "bench_suite_demo",
        .description = "Benchmark example driven by the first-class bench API",
        .source_files = &.{"examples/bench_suite/src/main.cpp"},
        .cpp_std = "17",
        .configs = cpp.BuildConfigs.release_only,
    });

    _ = test_suite.addBench(b, target, .{
        .name = "bench-suite",
        .target = bench,
        .cases = &.{
            .{ .label = "compute" },
        },
    }) catch @panic("failed to declare bench-suite");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    addSteps(b, target);
}
