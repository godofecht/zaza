const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    report_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, optimize: std.builtin.OptimizeMode) BuildResult {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
        .abi = .musl,
    });

    const exe = b.addExecutable(.{
        .name = "wasm_wasi_demo",
        .root_source_file = b.path("examples/wasm_wasi/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const install = b.addInstallArtifact(exe, .{});
    const build_step = b.step("wasm-wasi", "Build the WASI WebAssembly example");
    build_step.dependOn(&install.step);

    const report = b.addSystemCommand(&.{
        "node",
        "-e",
        "const fs=require('fs'); const p=process.argv[1]; const bytes=fs.readFileSync(p); console.log(WebAssembly.validate(bytes)?'wasm wasi valid':'wasm wasi invalid');",
        "zig-out/bin/wasm_wasi_demo.wasm",
    });
    report.setName("wasm-wasi-report-cmd");
    report.stdio = .inherit;
    report.step.dependencies.append(&install.step) catch unreachable;

    const report_step = b.step("wasm-wasi-report", "Validate the WASI WebAssembly artifact");
    report_step.dependOn(&report.step);

    return .{
        .build_step = build_step,
        .report_step = report_step,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, optimize);
}
