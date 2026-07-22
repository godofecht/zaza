const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addSteps(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) BuildResult {
    const common_flags = &.{
        "-std=c++17",
        "-DGRAPH_API_LEVEL=4",
    };

    const graph_objects = b.addObject(.{
        .name = "graph_objects",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    graph_objects.root_module.addCSourceFiles(.{
        .files = &.{"examples/interface_object_graph/src/object_part.cpp"},
        .flags = common_flags,
    });
    graph_objects.root_module.addIncludePath(b.path("examples/interface_object_graph/include"));
    graph_objects.root_module.link_libcpp = true;

    const graph_core = b.addLibrary(.{
        .name = "graph_core",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    graph_core.root_module.addCSourceFiles(.{
        .files = &.{"examples/interface_object_graph/src/core.cpp"},
        .flags = common_flags,
    });
    graph_core.root_module.addIncludePath(b.path("examples/interface_object_graph/include"));
    graph_core.root_module.addObject(graph_objects);
    graph_core.root_module.link_libcpp = true;

    const exe = b.addExecutable(.{
        .name = "interface_object_graph_demo",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addCSourceFiles(.{
        .files = &.{"examples/interface_object_graph/src/main.cpp"},
        .flags = common_flags,
    });
    exe.root_module.addIncludePath(b.path("examples/interface_object_graph/include"));
    exe.root_module.link_libcpp = true;
    exe.root_module.linkLibrary(graph_core);

    const build_step = b.step("interface-object-graph", "Build the interface/object/static graph example");
    build_step.dependOn(&b.addInstallArtifact(graph_core, .{}).step);
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("interface-object-graph-run", "Run the interface/object/static graph example");
    run_step.dependOn(&run.step);

    return .{
        .build_step = build_step,
        .run_step = run_step,
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = addSteps(b, target, optimize);
}
