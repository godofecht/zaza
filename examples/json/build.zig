const std = @import("std");
const BuildManager = @import("build_steps.zig").BuildManager;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var manager = BuildManager.init(b);
    defer manager.deinit();

    // Create all build steps with their log messages
    const create_deps = try manager.createStep("create_deps", "Creating deps directory");
    const clone_json = try manager.createStep("clone_json", "Cloning nlohmann/json repository");
    const build_json = try manager.createStep("build_json", "Configuring and building nlohmann/json");
    const build_exe = try manager.createStep("build_exe", "Building C++ example");
    const install_exe = try manager.createStep("install_exe", "Installing JSON example");

    // Add the actual build commands to each step
    if (create_deps.log_step) |_| {
        const cmd = b.addSystemCommand(&.{ "cmd.exe", "/c", "if not exist deps mkdir deps" });
        cmd.stdio = .inherit;
        create_deps.cmd_step = &cmd.step;
    }

    if (clone_json.log_step) |_| {
        const cmd = b.addSystemCommand(&.{
            "cmd.exe", "/c",
            "if not exist deps\\json\\include\\nlohmann\\json.hpp (" ++
                "if exist deps\\json rmdir /s /q deps\\json && " ++
                "git clone --depth 1 https://github.com/nlohmann/json.git deps/json" ++
            ")",
        });
        cmd.stdio = .inherit;
        clone_json.cmd_step = &cmd.step;
    }

    if (build_json.log_step) |_| {
        const cmd = b.addSystemCommand(&.{
            "cmd.exe",
            "/c",
            "cmake -S deps/json -B build/json -DCMAKE_BUILD_TYPE=Release -DJSON_BuildTests=OFF -DJSON_MultipleHeaders=ON && cmake --build build/json --config Release --verbose",
        });
        cmd.stdio = .inherit;
        build_json.cmd_step = &cmd.step;
    }

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "json_example",
        .target = target,
        .optimize = optimize,
        .root_source_file = null,
    });

    exe.addCSourceFile(.{
        .file = .{ .path = "src/main.cpp" },
        .flags = &.{
            "-std=c++17",
            "-fno-sanitize=undefined",
        },
    });
    exe.addIncludePath(.{ .path = "deps/json/include" });
    exe.linkLibCpp();

    try manager.addBuildCommand(build_exe, exe);
    try manager.addInstallCommand(install_exe, exe);

    // Set up the dependency chain
    try manager.addDependency(create_deps, clone_json);
    try manager.addDependency(clone_json, build_json);
    try manager.addDependency(build_json, build_exe);
    try manager.addDependency(build_exe, install_exe);

    // Get the final build step that includes all dependencies in the right order
    const final_step = try manager.getFinalStep();
    b.default_step.dependOn(final_step);
}
