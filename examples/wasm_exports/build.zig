const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
    web_step: *std.Build.Step,
    web_smoke_step: *std.Build.Step,
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

    const web_root = "zig-out/www/wasm-exports";
    const install_web_wasm = b.addInstallFileWithDir(exe.getEmittedBin(), .prefix, "www/wasm-exports/wasm_exports_demo.wasm");
    const install_web_html = b.addInstallFileWithDir(
        b.path("examples/wasm_exports/web/index.html"),
        .prefix,
        "www/wasm-exports/index.html",
    );
    const install_web_js = b.addInstallFileWithDir(
        b.path("examples/wasm_exports/web/app.js"),
        .prefix,
        "www/wasm-exports/app.js",
    );

    const web_step = b.step("wasm-web-demo", "Stage the browser WebAssembly demo");
    web_step.dependOn(&install_web_wasm.step);
    web_step.dependOn(&install_web_html.step);
    web_step.dependOn(&install_web_js.step);

    const server = b.addExecutable(.{
        .name = "zaza_static_server",
        .root_source_file = b.path("build_lib/static_server.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });

    const web_smoke = b.addRunArtifact(server);
    web_smoke.setName("wasm-web-demo-smoke-cmd");
    web_smoke.addArg("smoke");
    web_smoke.addArg(web_root);
    web_smoke.addArg("8123");
    web_smoke.addArg("/index.html");
    web_smoke.addArg("/app.js");
    web_smoke.addArg("/wasm_exports_demo.wasm");
    web_smoke.stdio = .inherit;
    web_smoke.step.dependencies.append(web_step) catch unreachable;

    const web_smoke_step = b.step("wasm-web-demo-smoke", "Smoke-test the staged browser WebAssembly demo");
    web_smoke_step.dependOn(&web_smoke.step);

    const serve = b.addRunArtifact(server);
    serve.setName("wasm-web-demo-serve-cmd");
    serve.addArg("serve");
    serve.addArg(web_root);
    serve.addArg("8000");
    serve.stdio = .inherit;
    serve.step.dependencies.append(web_step) catch unreachable;

    const serve_step = b.step("wasm-web-demo-serve", "Serve the browser WebAssembly demo at http://127.0.0.1:8000");
    serve_step.dependOn(&serve.step);

    return .{
        .build_step = build_step,
        .run_step = run_step,
        .web_step = web_step,
        .web_smoke_step = web_smoke_step,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, optimize);
}
