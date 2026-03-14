const std = @import("std");
const zaza_cmd = @import("../../build_lib/zaza_cmd.zig");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build) BuildResult {
    const compiler = std.process.getEnvVarOwned(b.allocator, "ZAZA_MODULES_CXX") catch
        "/opt/homebrew/opt/llvm/bin/clang++";

    const ensure_dirs = zaza_cmd.addCommandStep(
        b,
        "cxx20-modules-mkdir",
        &.{ "sh", "-c", "mkdir -p zig-out/modules zig-out/bin" },
    );

    const precompile = zaza_cmd.addCommandStep(
        b,
        "cxx20-modules-precompile",
        &.{
            compiler,
            "-std=c++20",
            "--precompile",
            "examples/cxx20_modules/src/math.cppm",
            "-o",
            "zig-out/modules/math.pcm",
        },
    );
    precompile.dependencies.append(ensure_dirs) catch unreachable;

    const compile_module = zaza_cmd.addCommandStep(
        b,
        "cxx20-modules-compile",
        &.{
            compiler,
            "-std=c++20",
            "-c",
            "examples/cxx20_modules/src/math.cppm",
            "-fmodule-file=math=zig-out/modules/math.pcm",
            "-o",
            "zig-out/modules/math.o",
        },
    );
    compile_module.dependencies.append(precompile) catch unreachable;

    const link = zaza_cmd.addCommandStep(
        b,
        "cxx20-modules-link",
        &.{
            compiler,
            "-std=c++20",
            "examples/cxx20_modules/src/main.cpp",
            "zig-out/modules/math.o",
            "-fmodule-file=math=zig-out/modules/math.pcm",
            "-o",
            "zig-out/bin/cxx20_modules_demo",
        },
    );
    link.dependencies.append(compile_module) catch unreachable;

    const build_step = b.step("cxx20-modules", "Build the C++20 modules example");
    build_step.dependOn(link);

    const run = zaza_cmd.addCommandStep(
        b,
        "cxx20-modules-runner",
        &.{ "zig-out/bin/cxx20_modules_demo" },
    );
    run.dependencies.append(link) catch unreachable;

    const run_step = b.step("cxx20-modules-run", "Run the C++20 modules example");
    run_step.dependOn(run);

    return .{
        .build_step = build_step,
        .run_step = run_step,
    };
}

pub fn build(b: *std.Build) void {
    _ = addSteps(b);
}
