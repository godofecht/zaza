//! First-class test and benchmark targets for Zaza builds.
//!
//! A test or benchmark is an executable plus a list of run cases. Each case is
//! data: a label, arguments, environment, and a working directory. This module
//! turns that data into the run steps and the per-case and aggregate build
//! steps, so a build file declares what to run rather than wiring run steps by
//! hand.
//!
//! Two entry points share one implementation and differ only in defaults:
//!
//!   addTest  hooks the aggregate onto the top `test` step, does not forward
//!            `zig build -- ...` arguments, and captures child output.
//!   addBench leaves the aggregate off the `test` step, forwards `-- ...`
//!            arguments to every case, and inherits stdio so timings print.
//!
//! The compiler and optimize mode come from the `CppExample.configs` the caller
//! provides, the same way the rest of Zaza chooses them. A benchmark target sets
//! `.configs = cpp.BuildConfigs.release_only`; a test target leaves the default.
//! The target is built through `CppExample.buildWithTarget`, so a test and the
//! normal build compile with identical flags.

const std = @import("std");
const cpp = @import("cpp_example.zig");

pub const EnvVar = struct {
    name: []const u8,
    value: []const u8,
};

/// One thing to run against the built executable.
pub const RunCase = struct {
    /// Names the run step and the per-case build step (`<name>-<label>`).
    label: []const u8,
    args: []const []const u8 = &.{},
    env: []const EnvVar = &.{},
    cwd: ?std.Build.LazyPath = null,
};

pub const Result = struct {
    /// The built executable the cases run against.
    exe: *std.Build.Step.Compile,
    /// Builds the executable (`<name>`).
    build_step: *std.Build.Step,
    /// Runs every case (`<name>-run`).
    run_step: *std.Build.Step,
    /// One step per case, same order as `cases` (`<name>-<label>`).
    case_steps: []*std.Build.Step,
};

pub const TestOptions = struct {
    /// Step namespace. Produces `test-foo`, `test-foo-run`, `test-foo-unit`, ...
    /// Callers pass the full prefix, e.g. `"test-workflows"`.
    name: []const u8,
    target: cpp.CppExample,
    cases: []const RunCase,
    /// Attach the aggregate run to the top `test` step so `zig build test`
    /// includes it.
    hook_test_step: bool = true,
};

pub const BenchOptions = struct {
    name: []const u8,
    target: cpp.CppExample,
    cases: []const RunCase,
    /// Benchmarks stay off `test` by default: they are slow and measure, they
    /// do not assert.
    hook_test_step: bool = false,
    /// Forward `zig build <step> -- --reps 9` to every case.
    forward_args: bool = true,
};

const Flavor = enum { test_suite, bench_suite };

const SuiteSpec = struct {
    name: []const u8,
    target: cpp.CppExample,
    cases: []const RunCase,
    hook_test_step: bool,
    flavor: Flavor,
    forward_args: bool,
};

/// Declare a test target: an executable plus labelled run cases.
pub fn addTest(b: *std.Build, target: std.Build.ResolvedTarget, options: TestOptions) !Result {
    return addSuite(b, target, .{
        .name = options.name,
        .target = options.target,
        .cases = options.cases,
        .hook_test_step = options.hook_test_step,
        .flavor = .test_suite,
        .forward_args = false,
    });
}

/// Declare a benchmark target. Same shape as a test, release defaults, kept off
/// the `test` step, with `-- ...` arguments forwarded to each case.
pub fn addBench(b: *std.Build, target: std.Build.ResolvedTarget, options: BenchOptions) !Result {
    return addSuite(b, target, .{
        .name = options.name,
        .target = options.target,
        .cases = options.cases,
        .hook_test_step = options.hook_test_step,
        .flavor = .bench_suite,
        .forward_args = options.forward_args,
    });
}

fn addSuite(b: *std.Build, target: std.Build.ResolvedTarget, spec: SuiteSpec) !Result {
    const exe = try spec.target.buildWithTarget(b, target);

    const build_desc = b.fmt("Build the {s} target", .{spec.name});
    const build_step = b.step(spec.name, build_desc);
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run_desc = switch (spec.flavor) {
        .test_suite => b.fmt("Run every case in {s}", .{spec.name}),
        .bench_suite => b.fmt("Run every benchmark in {s}", .{spec.name}),
    };
    const run_step = b.step(b.fmt("{s}-run", .{spec.name}), run_desc);

    const case_steps = try b.allocator.alloc(*std.Build.Step, spec.cases.len);

    for (spec.cases, 0..) |case, i| {
        const run = b.addRunArtifact(exe);
        run.setName(b.fmt("{s}-{s}", .{ spec.name, case.label }));
        if (case.cwd) |cwd| run.setCwd(cwd);
        for (case.env) |ev| run.setEnvironmentVariable(ev.name, ev.value);
        if (case.args.len > 0) run.addArgs(case.args);
        // Forwarded arguments come last so they win over the declared ones.
        if (spec.forward_args) {
            if (b.args) |extra| run.addArgs(extra);
        }
        // Benchmarks report to the terminal; tests capture so failures surface
        // as a failed step rather than as noise.
        if (spec.flavor == .bench_suite) run.stdio = .inherit;

        const case_desc = switch (spec.flavor) {
            .test_suite => b.fmt("Run the {s} case of {s}", .{ case.label, spec.name }),
            .bench_suite => b.fmt("Run the {s} benchmark of {s}", .{ case.label, spec.name }),
        };
        const case_step = b.step(b.fmt("{s}-{s}", .{ spec.name, case.label }), case_desc);
        case_step.dependOn(&run.step);
        run_step.dependOn(&run.step);
        case_steps[i] = case_step;
    }

    if (spec.hook_test_step) {
        const top = b.top_level_steps.get("test");
        if (top) |tls| tls.step.dependOn(run_step);
    }

    return .{
        .exe = exe,
        .build_step = build_step,
        .run_step = run_step,
        .case_steps = case_steps,
    };
}
