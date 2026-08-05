const std = @import("std");
const zaza = @import("zaza").api;

// Dear ImGui sources are fetched by ./fetch.sh into vendor/imgui (git-ignored).
const imgui_dir = "vendor/imgui";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    b.build_root.handle.access(imgui_dir ++ "/imgui.h", .{}) catch {
        std.debug.print(
            \\error: Dear ImGui sources not found under {s}.
            \\       run ./fetch.sh first to check out the pinned imgui slice.
            \\
        , .{imgui_dir});
        return error.UpstreamSourcesMissing;
    };

    // Dear ImGui core as a Zaza static-library target. These four translation
    // units are the platform- and renderer-independent core: no GL, no X11, no
    // windowing backend, so the slice builds headless. This is the "C/C++
    // library dependency graph" the corpus issue calls for, minus the system
    // GL that a full glfw/imgui sample would drag in.
    var imgui_lib = zaza.Target.staticLibrary(.{
        .name = "imgui",
        .description = "Dear ImGui core, built as a Zaza C++ target slice",
        .source_files = &.{
            imgui_dir ++ "/imgui.cpp",
            imgui_dir ++ "/imgui_draw.cpp",
            imgui_dir ++ "/imgui_tables.cpp",
            imgui_dir ++ "/imgui_widgets.cpp",
        },
        .public_include_dirs = &.{imgui_dir},
        .cpp_std = "17",
        .configs = &.{.{ .mode = .Release }},
    });
    const imgui_compile = try imgui_lib.buildWithTarget(b, target);

    // A headless consumer: it creates an ImGui context, builds the font atlas,
    // runs a few frames of a real widget tree, and reads back the generated
    // draw data. No GPU is touched, so it proves the core library links and
    // executes end to end.
    var consumer = zaza.Target.executable(.{
        .name = "imgui_consumer",
        .description = "Headless consumer that renders an ImGui frame via the Zaza-built slice",
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{imgui_dir},
        .cpp_std = "17",
        .configs = &.{.{ .mode = .Release }},
    });
    const consumer_compile = try consumer.buildWithTarget(b, target);
    consumer_compile.linkLibrary(imgui_compile);

    b.installArtifact(imgui_compile);
    b.installArtifact(consumer_compile);

    const run = b.addRunArtifact(consumer_compile);
    const run_step = b.step("run", "Build the imgui slice and run the headless consumer");
    run_step.dependOn(&run.step);
}
