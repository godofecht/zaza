const std = @import("std");
const zaza = @import("zaza").api;

const imgui = "vendor/imgui";
const backends = "vendor/imgui/backends";

// Zig 0.16 moved the filesystem under std.Io, so Dir.access takes the build
// graph's Io handle. Only the taken branch is analysed.
fn buildRootHas(b: *std.Build, sub_path: []const u8) bool {
    const r = if (comptime @hasDecl(std.fs, "cwd"))
        b.build_root.handle.access(sub_path, .{})
    else
        b.build_root.handle.access(b.graph.io, sub_path, .{});
    return if (r) |_| true else |_| false;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    if (!buildRootHas(b, backends ++ "/imgui_impl_glfw.cpp")) {
        std.debug.print(
            \\error: Dear ImGui (with backends) not found under {s}.
            \\       run ./fetch.sh first to check out the pinned imgui release.
            \\
        , .{imgui});
        return error.UpstreamSourcesMissing;
    }

    // Dear ImGui core + the GLFW and OpenGL3 backends, as a Zaza static-library
    // target. Unlike the core-only imgui slice, this links a real windowing and
    // GL backend, so it exercises the C/C++ graph with system libraries.
    var imgui_lib = zaza.Target.staticLibrary(.{
        .name = "imgui_glfw",
        .description = "Dear ImGui + GLFW/OpenGL3 backends, built as a Zaza C++ target slice",
        .source_files = &.{
            imgui ++ "/imgui.cpp",
            imgui ++ "/imgui_draw.cpp",
            imgui ++ "/imgui_tables.cpp",
            imgui ++ "/imgui_widgets.cpp",
            backends ++ "/imgui_impl_glfw.cpp",
            backends ++ "/imgui_impl_opengl3.cpp",
        },
        .public_include_dirs = &.{ imgui, backends },
        .cpp_std = "17",
        .configs = &.{.{ .mode = .Release }},
    });
    const imgui_compile = try imgui_lib.buildWithTarget(b, target);

    // A consumer that opens a GLFW window, creates a GL context, and renders a
    // real ImGui frame through the backends. It runs headless under a virtual
    // framebuffer with software GL (see PROOF.md).
    var consumer = zaza.Target.executable(.{
        .name = "imgui_glfw_consumer",
        .description = "Consumer that renders an ImGui frame over GLFW + OpenGL3",
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{ imgui, backends },
        // System windowing and GL libraries provided by the platform.
        .public_link_libs = &.{ "glfw", "GL" },
        .cpp_std = "17",
        .configs = &.{.{ .mode = .Release }},
    });
    const consumer_compile = try consumer.buildWithTarget(b, target);
    consumer_compile.root_module.linkLibrary(imgui_compile);

    b.installArtifact(imgui_compile);
    b.installArtifact(consumer_compile);

    const run = b.addRunArtifact(consumer_compile);
    const run_step = b.step("run", "Build the imgui+glfw slice and run the consumer");
    run_step.dependOn(&run.step);
}
