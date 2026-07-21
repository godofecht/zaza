const std = @import("std");

pub fn build(b: *std.Build) !void {
    const exe = b.addExecutable(.{
        .name = "simple_example",
        // C++ executable,
        .root_module = b.createModule(.{
            .root_source_file = null,
        }),
    });
    
    // Add C++ source file
    exe.addCSourceFile(.{
        .file = b.path("simple_example.cpp"),
        .flags = &.{"-std=c++17"},
    });
    
    // Link C++ runtime
    exe.linkLibCpp();
    
    // Install the executable
    b.installArtifact(exe);
    
    // Add a run step
    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run-simple", "Run the simple C++ example");
    run_step.dependOn(&run_cmd.step);
}
