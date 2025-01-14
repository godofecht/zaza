const std = @import("std");
const zigcpp = @import("zigcpp.zig");

pub const Platform = struct {
    arch: std.Target.Cpu.Arch,
    os: std.Target.Os.Tag,
    name: []const u8,

    pub fn target(self: Platform) std.zig.CrossTarget {
        return .{
            .cpu_arch = self.arch,
            .os_tag = self.os,
        };
    }

    // Common platforms
    pub const linux_x64 = Platform{ .arch = .x86_64, .os = .linux, .name = "linux-x64" };
    pub const windows_x64 = Platform{ .arch = .x86_64, .os = .windows, .name = "windows-x64" };
    pub const linux_arm64 = Platform{ .arch = .aarch64, .os = .linux, .name = "linux-arm64" };
    pub const macos_arm64 = Platform{ .arch = .aarch64, .os = .macos, .name = "macos-arm64" };
    pub const macos_x64 = Platform{ .arch = .x86_64, .os = .macos, .name = "macos-x64" };
    pub const wasm = Platform{ .arch = .wasm32, .os = .wasi, .name = "wasm" };

    pub const desktop = [_]Platform{
        linux_x64,
        windows_x64,
        macos_x64,
        macos_arm64,
    };

    pub const all = [_]Platform{
        linux_x64,
        windows_x64,
        linux_arm64,
        macos_x64,
        macos_arm64,
        wasm,
    };
};

pub const Example = struct {
    name: []const u8,
    description: []const u8,
    source_files: []const []const u8,
    platforms: []const Platform = &Platform.desktop,
    dependencies: []const []const u8 = &.{},
    cpp_standard: []const u8 = "20",
    defines: []const []const u8 = &.{},
    include_paths: []const []const u8 = &.{},
    deps_dir: ?[]const u8 = null,  // Optional override for deps directory

    pub fn build(
        self: Example,
        b: *std.Build,
        optimize: std.builtin.OptimizeMode,
    ) !*std.Build.Step {
        const step = b.step(self.name, self.description);

        for (self.platforms) |platform| {
            var app = zigcpp.Cpp.createWithOptions(
                b,
                b.fmt("{s}-{s}", .{ self.name, platform.name }),
                .executable,
                platform.target(),
                optimize,
            );
            defer app.deinit();

            // Set custom deps directory if provided
            if (self.deps_dir) |dir| {
                app.setDepsDir(dir);
            }

            // Configure
            _ = app.standard(self.cpp_standard)
                .defines(self.defines)
                .includes(self.include_paths);

            // Add dependencies
            for (self.dependencies) |dep| {
                _ = app.addGithubDependency(dep);
            }

            // Add sources
            _ = app.addSources(self.source_files);

            try app.build();
            step.dependOn(&b.addInstallArtifact(app.artifact, .{}).step);
        }

        return step;
    }
}; 