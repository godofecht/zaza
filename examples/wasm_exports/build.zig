const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, optimize: std.builtin.OptimizeMode) BuildResult {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const exe = b.addExecutable(.{
        .name = "wasm_exports_demo",
        .root_source_file = b.path("examples/wasm_exports/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.entry = .disabled;
    exe.rdynamic = true;

    const install = b.addInstallArtifact(exe, .{});
    const build_step = b.step("wasm-exports", "Build the freestanding WebAssembly exports example");
    build_step.dependOn(&install.step);

    const run = b.addSystemCommand(&.{
        "node",
        "-e",
        "const fs=require('fs'); WebAssembly.instantiate(fs.readFileSync(process.argv[1])).then(({instance})=>{ console.log('wasm add:', instance.exports.add(20,22)); console.log('wasm mul_add:', instance.exports.mul_add(6,6,6)); }).catch(err=>{ console.error(err); process.exit(1); });",
        "zig-out/bin/wasm_exports_demo.wasm",
    });
    run.setName("wasm-exports-runner");
    run.stdio = .inherit;
    run.step.dependencies.append(&install.step) catch unreachable;

    const run_step = b.step("wasm-exports-run", "Run the freestanding WebAssembly exports example via Node");
    run_step.dependOn(&run.step);

    return .{
        .build_step = build_step,
        .run_step = run_step,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, optimize);
}
