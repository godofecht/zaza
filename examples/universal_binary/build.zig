// Universal-binary example: build a program for both macOS architectures and
// combine the slices into one Mach-O universal binary with zaza-lipo.
//
// This is the pipeline half of zaza#38. Zig cross-compiles both macOS slices
// from any host, and zaza-lipo (build_lib/fatbinary.zig) combines them without
// Apple's lipo, so the whole example builds and reports on a Linux CI runner as
// well as on macOS. Only running the result needs a Mac.

const std = @import("std");

pub const BuildResult = struct {
    build_step: *std.Build.Step,
    report_step: *std.Build.Step,
};

fn slice(
    b: *std.Build,
    name: []const u8,
    arch: std.Target.Cpu.Arch,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/universal_binary/src/main.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = arch, .os_tag = .macos }),
            .optimize = optimize,
        }),
    });
}

pub fn addSteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) BuildResult {
    _ = target; // universal binaries are macOS-specific, so the slices are pinned.

    const x86 = slice(b, "universal_binary_demo_x86_64", .x86_64, optimize);
    const arm = slice(b, "universal_binary_demo_arm64", .aarch64, optimize);

    // Build the portable combiner in this graph.
    const lipo = b.addExecutable(.{
        .name = "zaza-lipo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zaza-lipo/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    lipo.root_module.addImport("fatbinary", b.createModule(.{
        .root_source_file = b.path("build_lib/fatbinary.zig"),
    }));
    lipo.root_module.addImport("compat", b.createModule(.{
        .root_source_file = b.path("build_lib/compat.zig"),
    }));

    // zaza-lipo create -arch x86_64 <slice> -arch arm64 <slice> -output <out>
    const combine = b.addRunArtifact(lipo);
    combine.addArg("create");
    combine.addArg("-arch");
    combine.addArg("x86_64");
    combine.addFileArg(x86.getEmittedBin());
    combine.addArg("-arch");
    combine.addArg("arm64");
    combine.addFileArg(arm.getEmittedBin());
    combine.addArg("-output");
    const universal = combine.addOutputFileArg("universal_binary_demo");

    const install = b.addInstallBinFile(universal, "universal_binary_demo");

    const build_step = b.step("universal-binary", "Build a macOS universal binary from x86_64 and arm64 slices");
    build_step.dependOn(&install.step);

    // Report: run zaza-lipo info on the combined artifact. It succeeds only on a
    // well-formed fat file, so it doubles as a smoke check of the combine step.
    const info = b.addRunArtifact(lipo);
    info.addArg("info");
    info.addFileArg(universal);
    info.stdio = .inherit;

    const report_step = b.step("universal-binary-report", "Combine the slices and inspect the universal binary");
    report_step.dependOn(&info.step);
    report_step.dependOn(&install.step);

    return .{ .build_step = build_step, .report_step = report_step };
}
