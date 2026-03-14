const std = @import("std");

const PackageManifest = struct {
    name: []const u8,
    kind: []const u8,
    include_dirs: []const []const u8,
    headers: []const []const u8,
    libs: []const []const u8,
    link_libraries: []const []const u8,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const package_prefix = b.option([]const u8, "package-prefix", "Prefix where the producer package was installed") orelse "../../zig-out";

    const manifest_path = b.pathJoin(&.{ package_prefix, "share", "zaza", "package_math.json" });
    const manifest = try readPackageManifest(b.allocator, manifest_path);

    const exe = b.addExecutable(.{
        .name = "package_consumer",
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{
        .files = &.{"src/main.cpp"},
        .flags = &.{"-std=c++17"},
    });
    exe.linkLibCpp();

    for (manifest.include_dirs) |dir| {
        exe.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ package_prefix, dir }) });
    }
    for (manifest.libs) |lib| {
        exe.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ package_prefix, lib }) });
    }
    for (manifest.link_libraries) |lib| {
        exe.linkSystemLibrary(lib);
    }

    const build_step = b.step("package-consumer", "Build the downstream package consumer");
    build_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the downstream package consumer");
    run_step.dependOn(&run.step);
}

fn readPackageManifest(allocator: std.mem.Allocator, path: []const u8) !PackageManifest {
    const file = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(file);

    const parsed = try std.json.parseFromSlice(PackageManifest, allocator, file, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    return parsed.value;
}
