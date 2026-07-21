const std = @import("std");

/// A Rust crate that can be built via Cargo and linked into a Zig build graph.
///
/// Strategy: Cargo builds the Rust static lib, `zig build-obj` compiles Zig to a .o,
/// and the system `cc` links them together. This bypasses Zig 0.14's internal Mach-O
/// linker which cannot parse Rust-produced archives.
pub const RustExample = struct {
    /// Name of the crate (must match `[lib] name` in Cargo.toml).
    name: []const u8,
    /// Path to the crate directory (containing Cargo.toml), relative to the repo root.
    crate_dir: []const u8,
    /// Extra flags passed to `cargo build`.
    extra_cargo_args: []const []const u8 = &.{},

    pub const BuildResult = struct {
        build_step: *std.Build.Step,
        run_step: *std.Build.Step,
    };

    /// Add full build + run steps for a Zig executable that links a Rust static library.
    pub fn addSteps(
        self: RustExample,
        b: *std.Build,
        _: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        zig_source: []const u8,
        exe_name: []const u8,
    ) BuildResult {
        const release = switch (optimize) {
            .Debug => false,
            else => true,
        };
        const profile = if (release) "release" else "debug";

        // Detect real machine arch (handles Rosetta: x86_64 zig on arm64 hardware).
        const machine_arch = detectMachineArch(b);
        const zig_target = machineZigTarget(machine_arch);

        // --- Phase 0: Cargo build (no explicit --target; Cargo auto-detects native) ---
        const cargo = b.addSystemCommand(&.{
            "cargo", "build",
            "--manifest-path",
            b.fmt("{s}/Cargo.toml", .{self.crate_dir}),
        });
        if (release) cargo.addArg("--release");
        for (self.extra_cargo_args) |arg| cargo.addArg(arg);
        cargo.setName(b.fmt("cargo-build-{s}", .{self.name}));
        cargo.stdio = .inherit;

        // --- Phase 1: Compile Zig source to object file ---
        const obj_path = b.fmt("zig-out/obj/{s}.o", .{exe_name});
        const zig_compile = b.addSystemCommand(&.{
            "./zig",      "build-obj",
            zig_source,
            b.fmt("-I{s}/include", .{self.crate_dir}),
            b.fmt("-femit-bin={s}", .{obj_path}),
            "-target",
            zig_target,
        });
        zig_compile.setName(b.fmt("zig-obj-{s}", .{exe_name}));
        zig_compile.stdio = .inherit;

        // --- Phase 2: Link with system cc ---
        const lib_path = b.fmt("{s}/target/{s}/lib{s}.a", .{ self.crate_dir, profile, self.name });
        const out_path = b.fmt("zig-out/bin/{s}", .{exe_name});

        var link_argv = std.ArrayList([]const u8).init(b.allocator);
        link_argv.appendSlice(&.{ "cc", "-arch", machineAppleArch(machine_arch), obj_path, lib_path, "-o", out_path }) catch unreachable;
        link_argv.appendSlice(&.{ "-lSystem", "-framework", "Security", "-framework", "CoreFoundation" }) catch unreachable;
        const link_cmd = b.addSystemCommand(link_argv.toOwnedSlice() catch unreachable);
        link_cmd.setName(b.fmt("cc-link-{s}", .{exe_name}));
        link_cmd.stdio = .inherit;

        // Dependency chain: cargo + zig-obj → cc-link
        link_cmd.step.dependOn(&cargo.step);
        link_cmd.step.dependOn(&zig_compile.step);

        // Ensure output dirs exist.
        const mkdir_obj = b.addSystemCommand(&.{ "mkdir", "-p", "zig-out/obj" });
        const mkdir_bin = b.addSystemCommand(&.{ "mkdir", "-p", "zig-out/bin" });
        zig_compile.step.dependOn(&mkdir_obj.step);
        link_cmd.step.dependOn(&mkdir_bin.step);

        // --- Wrappers ---
        const build_step = b.step("rust-interop", b.fmt("Build the Rust interop example ({s})", .{exe_name}));
        build_step.dependOn(&link_cmd.step);

        const run = b.addSystemCommand(&.{out_path});
        run.stdio = .inherit;
        run.step.dependOn(&link_cmd.step);
        const run_step = b.step("rust-interop-run", b.fmt("Run the Rust interop example ({s})", .{exe_name}));
        run_step.dependOn(&run.step);

        return .{ .build_step = build_step, .run_step = run_step };
    }

    /// Add just the Cargo build step (useful when composing manually).
    pub fn addCargoBuildStep(
        self: RustExample,
        b: *std.Build,
        _: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) *std.Build.Step {
        const release = switch (optimize) {
            .Debug => false,
            else => true,
        };
        const cargo = b.addSystemCommand(&.{
            "cargo", "build",
            "--manifest-path",
            b.fmt("{s}/Cargo.toml", .{self.crate_dir}),
        });
        if (release) cargo.addArg("--release");
        for (self.extra_cargo_args) |arg| cargo.addArg(arg);
        cargo.setName(b.fmt("cargo-build-{s}", .{self.name}));
        cargo.stdio = .inherit;
        return &cargo.step;
    }
};

/// Detect the real machine architecture.
/// Handles Rosetta: when an x86_64 process calls `uname -m` on Apple Silicon,
/// it falsely reports x86_64. We detect this via `sysctl hw.optional.arm64`.
fn detectMachineArch(b: *std.Build) []const u8 {
    // First check if we're running under Rosetta on Apple Silicon.
    const sysctl_result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "sysctl", "-n", "hw.optional.arm64" },
    }) catch return detectViaUname(b);
    defer b.allocator.free(sysctl_result.stdout);
    defer b.allocator.free(sysctl_result.stderr);
    const val = std.mem.trim(u8, sysctl_result.stdout, " \t\r\n");
    if (std.mem.eql(u8, val, "1")) return "aarch64";
    return detectViaUname(b);
}

fn detectViaUname(b: *std.Build) []const u8 {
    const result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "uname", "-m" },
    }) catch return "x86_64";
    defer b.allocator.free(result.stderr);
    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "arm64")) {
        b.allocator.free(result.stdout);
        return "aarch64";
    }
    return trimmed;
}

/// Convert a machine arch string to a Zig target triple for macOS.
/// Falls back to native for non-macOS (the common case for this project).
fn machineZigTarget(arch: []const u8) []const u8 {
    if (std.mem.eql(u8, arch, "aarch64")) return "aarch64-macos";
    if (std.mem.eql(u8, arch, "x86_64")) return "x86_64-macos";
    return "native";
}

/// Convert internal arch name to Apple's `-arch` flag value.
fn machineAppleArch(arch: []const u8) []const u8 {
    if (std.mem.eql(u8, arch, "aarch64")) return "arm64";
    return arch; // x86_64 stays x86_64
}
