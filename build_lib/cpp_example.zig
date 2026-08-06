const std = @import("std");
const builtin = @import("builtin");
const zaza_cmd = @import("zaza_cmd.zig");

/// Zig 0.14 spells buffered formatting `list.writer(gpa).print(...)`; 0.16
/// removed `writer` and 0.15 added `list.print(gpa, ...)`. No single spelling
/// covers all three, so pick at comptime. Only the taken branch is analysed.
fn listPrint(
    out: *std.ArrayListUnmanaged(u8),
    gpa: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    if (comptime @hasDecl(@TypeOf(out.*), "writer")) {
        try out.writer(gpa).print(fmt, args);
    } else {
        try out.print(gpa, fmt, args);
    }
}

/// Zig 0.16 moved the filesystem under std.Io, so writes need the build
/// graph's Io handle. Only the taken branch is analysed.
fn readBuildRootFile(b: *std.Build, sub_path: []const u8) ?[]u8 {
    if (comptime @hasDecl(std.fs, "cwd")) {
        return b.build_root.handle.readFileAlloc(b.allocator, sub_path, 16 * 1024 * 1024) catch null;
    } else {
        return b.build_root.handle.readFileAlloc(b.graph.io, sub_path, b.allocator, .unlimited) catch null;
    }
}

fn writeBuildRootFile(b: *std.Build, sub_path: []const u8, data: []const u8) !void {
    // Only write when the content actually changed. These files are generated
    // on every configure, so an unconditional write both rewrites an identical
    // file on each no-op rebuild and leaves the generated output permanently
    // dirty in git status.
    if (readBuildRootFile(b, sub_path)) |existing| {
        defer b.allocator.free(existing);
        if (std.mem.eql(u8, existing, data)) return;
    }
    if (comptime @hasDecl(std.fs, "cwd")) {
        try b.build_root.handle.writeFile(.{ .sub_path = sub_path, .data = data });
    } else {
        try b.build_root.handle.writeFile(b.graph.io, .{ .sub_path = sub_path, .data = data });
    }
}

/// A source dependency: a name, a URL, and how to fetch and build it. A null
/// `type` means "use the parent target's build system".
pub const Dependency = struct {
    name: []const u8,
    url: []const u8,
    git_ref: ?[]const u8 = null,
    include_path: ?[]const u8 = null,
    type: ?BuildSystem = null, // null means "use parent's build system"
    build_command: []const []const u8 = &.{},
    cmake_config: ?CMakeConfig = null,
    pkg_name: ?[]const u8 = null,
    pkg_include: ?[]const u8 = null,

    pub fn getBuildCommand(self: Dependency, b: *std.Build, config_name: []const u8, parent_build_system: BuildSystem) []const []const u8 {
        const effective_type = self.type orelse parent_build_system;
        if (effective_type == .CMake) {
            _ = b;
            _ = config_name;
            return &.{};
        }

        // For custom build commands or Zig
        return self.build_command;
    }
};

/// CMake settings for a dependency or a CMake-built target: source and build
/// directories, generator, toolchain, and the argument lists for each phase.
pub const CMakeConfig = struct {
    source_dir: ?[]const u8 = null,
    build_dir: ?[]const u8 = null,
    generator: ?[]const u8 = null,
    toolchain_file: ?[]const u8 = null,
    install_prefix: ?[]const u8 = null,
    install: bool = false,
    configure_args: []const []const u8 = &.{},
    build_args: []const []const u8 = &.{},
    install_args: []const []const u8 = &.{},
};

/// Common C++ preprocessor definitions
pub const Defines = struct {
    /// Enable exceptions (required for MSVC)
    pub const exceptions = "-D_HAS_EXCEPTIONS=1";
    /// Enable RTTI
    pub const rtti = "-D_CPPRTTI=1";
    /// Enable debug mode
    pub const debug = "-DDEBUG=1";
    /// Enable release mode
    pub const release = "-DNDEBUG=1";
    /// Disable warnings
    pub const no_warnings = "-D_CRT_SECURE_NO_WARNINGS";
    /// Unicode support
    pub const unicode = "-DUNICODE -D_UNICODE";
    /// Windows-specific
    pub const windows = "-DWIN32 -D_WINDOWS";
    /// DLL export
    pub const dll_export = "-DBUILDING_DLL";
    /// DLL import
    pub const dll_import = "-DUSING_DLL";

    /// Helper to create a custom define
    pub fn custom(b: *std.Build, name: []const u8, value: ?[]const u8) []const u8 {
        if (value) |v| {
            return b.fmt("-D{s}={s}", .{ name, v });
        }
        return b.fmt("-D{s}", .{name});
    }
};

/// Registry of common C++ dependencies
pub const Deps = struct {
    pub const nlohmann_json = Dependency{
        .name = "json",
        .url = "https://github.com/nlohmann/json.git",
        .include_path = "deps/json/single_include/nlohmann/json.hpp",
        .type = null, // Use parent's build system
        .build_command = &.{},
    };
};

/// Common build configurations
pub const BuildConfigs = struct {
    pub const debug_release: []const BuildConfig = &.{
        BuildConfig{
            .mode = .Debug,
            .defines = &.{"DEBUG=1"},
        },
        BuildConfig{
            .mode = .Release,
            .defines = &.{"NDEBUG=1"},
        },
    };

    pub const debug_only: []const BuildConfig = &.{
        BuildConfig{
            .mode = .Debug,
            .defines = &.{"DEBUG=1"},
        },
    };

    pub const release_only: []const BuildConfig = &.{
        BuildConfig{
            .mode = .Release,
            .defines = &.{"NDEBUG=1"},
        },
    };
};

/// The option bag accepted by the `CppExample` constructors. Most fields
/// default, so a target names only what it needs. `null` `configs` means the
/// debug-only default.
pub const TargetOptions = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    source_files: []const []const u8,
    include_dirs: []const []const u8 = &.{},
    public_include_dirs: []const []const u8 = &.{},
    private_include_dirs: []const []const u8 = &.{},
    cpp_flags: []const []const u8 = &.{},
    public_defines: []const []const u8 = &.{},
    private_defines: []const []const u8 = &.{},
    public_link_libs: []const []const u8 = &.{},
    private_link_libs: []const []const u8 = &.{},
    install_headers: []const []const u8 = &.{},
    install_libs: []const []const u8 = &.{},
    artifact_copies: []const ArtifactCopy = &.{},
    file_copies: []const FileCopy = &.{},
    export_cmake: bool = false,
    export_name: ?[]const u8 = null,
    generated_source_files: []const []const u8 = &.{},
    custom_commands: []const CustomCommand = &.{},
    post_build_commands: []const CustomCommand = &.{},
    deps: []const Dependency = &.{},
    configs: ?[]const BuildConfig = null,
    deps_build_system: BuildSystem = .Zig,
    main_build_system: BuildSystem = .Zig,
    cpp_std: ?[]const u8 = "17",
    /// Build this target as C instead of C++. When set (for example `"99"` or
    /// `"11"`), the target is compiled with `-std=c<c_std>`, the C++-only flags
    /// (`-frtti`, `-fexceptions`, `-D_HAS_EXCEPTIONS`) are dropped, and it links
    /// `libc` rather than `libc++`. `cpp_std` is ignored while this is set. Use
    /// it for C-only sources or C headers that do not compile as C++.
    c_std: ?[]const u8 = null,
    cmake_config: ?CMakeConfig = null,
    enable_system_commands: bool = false,
};

/// Whether a target or dependency builds through Zig or through CMake.
pub const BuildSystem = enum {
    Zig,
    CMake,
};

/// Which artifact a target produces.
pub const TargetKind = enum {
    executable,
    static_library,
    shared_library,
    object_library,
    interface_library,
};

/// How a usage requirement propagates across a dependency edge, mirroring
/// CMake's PUBLIC, PRIVATE, and INTERFACE.
pub const Visibility = enum {
    public,
    private,
    interface,
};

pub const UsageRequirements = struct {
    include_dirs: []const []const u8 = &.{},
    compile_definitions: []const []const u8 = &.{},
    compile_options: []const []const u8 = &.{},
    link_libraries: []const []const u8 = &.{},
    link_options: []const []const u8 = &.{},

    pub fn merge(self: UsageRequirements, allocator: std.mem.Allocator, other: UsageRequirements) !UsageRequirements {
        return .{
            .include_dirs = try concatSlices(allocator, self.include_dirs, other.include_dirs),
            .compile_definitions = try concatSlices(allocator, self.compile_definitions, other.compile_definitions),
            .compile_options = try concatSlices(allocator, self.compile_options, other.compile_options),
            .link_libraries = try concatSlices(allocator, self.link_libraries, other.link_libraries),
            .link_options = try concatSlices(allocator, self.link_options, other.link_options),
        };
    }
};

pub const TargetDependency = struct {
    name: []const u8,
    visibility: Visibility = .public,
};

pub const ResolvedUsage = struct {
    local: UsageRequirements = .{},
    exported: UsageRequirements = .{},
    link_libraries: []const []const u8 = &.{},
};

pub const CppTarget = struct {
    name: []const u8,
    kind: TargetKind = .executable,
    include_dirs: UsageRequirements = .{},
    dependencies: []const TargetDependency = &.{},

    pub fn resolveUsage(self: CppTarget, allocator: std.mem.Allocator, graph: []const CppTarget) !ResolvedUsage {
        var visiting = std.StringHashMap(void).init(allocator);
        defer visiting.deinit();
        return resolveUsageInner(allocator, self, graph, &visiting);
    }
};

/// Optimisation intent for a configuration. Mapped to Zig optimize modes when
/// built and to CMake build types when a CMake project is generated.
pub const BuildMode = enum {
    Debug,
    Release,
    RelWithDebInfo,
    MinSizeRel,

    pub fn toCMakeString(self: BuildMode) []const u8 {
        return switch (self) {
            .Debug => "Debug",
            .Release => "Release",
            .RelWithDebInfo => "RelWithDebInfo",
            .MinSizeRel => "MinSizeRel",
        };
    }

    pub fn toCompileFlags(self: BuildMode) []const []const u8 {
        return switch (self) {
            .Debug => &.{ "-g", "-O0" },
            .Release => &.{"-O3"},
            .RelWithDebInfo => &.{ "-g", "-O2" },
            .MinSizeRel => &.{"-Os"},
        };
    }
};

/// One build configuration: a mode plus the flags, defines, and link inputs
/// applied when a target is built in that mode. A target carries a list of
/// these in `configs`.
pub const BuildConfig = struct {
    mode: BuildMode,
    target: ?[]const u8 = null,
    defines: []const []const u8 = &.{},
    cpp_flags: []const []const u8 = &.{},
    system_includes: []const []const u8 = &.{},
    link_paths: []const []const u8 = &.{},
    link_libs: []const []const u8 = &.{},
    link_files: []const []const u8 = &.{},
    link_frameworks: []const []const u8 = &.{},
    want_lto: bool = false,
};

/// A named command that produces generated sources. It runs before compilation
/// and only when system commands are enabled on the target.
pub const CustomCommand = struct {
    name: []const u8,
    argv: []const []const u8,
};

/// Extra install-style copies of a built artifact. This is for plugin bundles,
/// staged app layouts, and package directories that need the same artifact in
/// more than Zig's default `bin`/`lib` output.
pub const ArtifactCopy = struct {
    /// Destination directory relative to the install prefix, for example
    /// `share/my_app/plugins` or `lib/vst3/MyPlugin.vst3/Contents/MacOS`.
    dest_dir: []const u8,
    /// Optional public step name. Defaults to `<target>-copy-<index>`.
    step_name: ?[]const u8 = null,
};

/// Install-style copies of source files or generated files into a stable output
/// layout. `dest_path` is relative to the install prefix and includes the file
/// name, for example `share/my_app/assets/preset.json`.
pub const FileCopy = struct {
    /// Source path relative to the build root, or any path accepted by
    /// `b.path(...)`.
    source_path: []const u8,
    /// Destination path relative to the install prefix, including the file name.
    dest_path: []const u8,
    /// Optional public step name. Defaults to `<target>-copy-file-<index>`.
    step_name: ?[]const u8 = null,
};

pub fn addArtifactCopies(
    b: *std.Build,
    target_name: []const u8,
    artifact: *std.Build.Step.Compile,
    copies: []const ArtifactCopy,
    dependency: ?*std.Build.Step,
) ?*std.Build.Step {
    if (copies.len == 0) return dependency;

    var last_step = dependency;
    for (copies, 0..) |copy, idx| {
        const install_copy = b.addInstallArtifact(artifact, .{
            .dest_dir = .{ .override = .{ .custom = copy.dest_dir } },
        });
        if (last_step) |prev| {
            install_copy.step.dependencies.append(prev) catch unreachable;
        }

        const step = b.step(
            copy.step_name orelse b.fmt("{s}-copy-{d}", .{ target_name, idx }),
            b.fmt("Copy {s} artifact to {s}", .{ target_name, copy.dest_dir }),
        );
        step.dependOn(&install_copy.step);
        last_step = step;
    }
    return last_step;
}

pub fn addFileCopies(
    b: *std.Build,
    target_name: []const u8,
    copies: []const FileCopy,
    dependency: ?*std.Build.Step,
) ?*std.Build.Step {
    if (copies.len == 0) return dependency;

    var last_step = dependency;
    for (copies, 0..) |copy, idx| {
        const install_copy = b.addInstallFileWithDir(
            b.path(copy.source_path),
            .prefix,
            copy.dest_path,
        );
        if (last_step) |prev| {
            install_copy.step.dependencies.append(prev) catch unreachable;
        }

        const step = b.step(
            copy.step_name orelse b.fmt("{s}-copy-file-{d}", .{ target_name, idx }),
            b.fmt("Copy {s} to {s}", .{ copy.source_path, copy.dest_path }),
        );
        step.dependOn(&install_copy.step);
        last_step = step;
    }
    return last_step;
}

fn addPostBuildCommands(
    b: *std.Build,
    self: CppExample,
    config_name: []const u8,
    dependency: ?*std.Build.Step,
) !?*std.Build.Step {
    if (self.post_build_commands.len == 0) return null;
    if (!self.enable_system_commands) {
        std.log.err(
            "target '{s}': post-build command '{s}' needs system commands, which are disabled. " ++
                "Enable with -Dsystem-cmds=true or ZAZA_SYSTEM_CMDS=1.",
            .{ self.name, self.post_build_commands[0].name },
        );
        return error.SystemCommandsDisabled;
    }

    var last_step = dependency;
    for (self.post_build_commands) |cmd| {
        const post_step = zaza_cmd.addCommandStep(
            b,
            b.fmt("{s}_{s}", .{ cmd.name, config_name }),
            cmd.argv,
        );
        if (last_step) |prev| {
            post_step.dependencies.append(prev) catch unreachable;
        }
        last_step = post_step;
    }
    return last_step;
}

pub fn dependencySyncScript(allocator: std.mem.Allocator, dep: Dependency, windows: bool) []const u8 {
    const url = normalizeGitUrlFromAllocator(allocator, dep.url);
    if (windows) {
        if (dep.git_ref) |git_ref| {
            return std.fmt.allocPrint(
                allocator,
                "if exist deps\\{0s}\\.git (git -C deps\\{0s} fetch --tags origin {1s} || git -C deps\\{0s} fetch --tags) && git -C deps\\{0s} checkout --force {1s} else (git clone --depth 1 --branch {1s} {2s} deps/{0s} || (git clone {2s} deps/{0s} && git -C deps\\{0s} checkout --force {1s}))",
                .{ dep.name, git_ref, url },
            ) catch unreachable;
        }
        return std.fmt.allocPrint(
            allocator,
            "if not exist deps\\{0s}\\.git git clone --depth 1 {1s} deps/{0s}",
            .{ dep.name, url },
        ) catch unreachable;
    }
    if (dep.git_ref) |git_ref| {
        return std.fmt.allocPrint(
            allocator,
            "if test -d deps/{0s}/.git; then (git -C deps/{0s} fetch --tags origin {1s} || git -C deps/{0s} fetch --tags) && git -C deps/{0s} checkout --force {1s}; else git clone --depth 1 --branch {1s} {2s} deps/{0s} || (git clone {2s} deps/{0s} && git -C deps/{0s} checkout --force {1s}); fi",
            .{ dep.name, git_ref, url },
        ) catch unreachable;
    }
    return std.fmt.allocPrint(
        allocator,
        "test -d deps/{0s}/.git || git clone --depth 1 {1s} deps/{0s}",
        .{ dep.name, url },
    ) catch unreachable;
}

fn makeCloneCommand(b: *std.Build, dep: Dependency) []const []const u8 {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    if (builtin.os.tag == .windows) {
        args.appendSlice(b.allocator, &.{
            "cmd.exe",
            "/c",
            dependencySyncScript(b.allocator, dep, true),
        }) catch unreachable;
    } else {
        args.appendSlice(b.allocator, &.{
            "sh",
            "-c",
            dependencySyncScript(b.allocator, dep, false),
        }) catch unreachable;
    }
    return args.toOwnedSlice(b.allocator) catch unreachable;
}

fn makeSubmoduleInitCommand(b: *std.Build, dep_name: []const u8) []const []const u8 {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    if (builtin.os.tag == .windows) {
        args.appendSlice(b.allocator, &.{
            "cmd.exe",
            "/c",
            b.fmt("cd deps\\{s} && git submodule update --init --recursive", .{dep_name}),
        }) catch unreachable;
    } else {
        args.appendSlice(b.allocator, &.{
            "sh",
            "-c",
            b.fmt("cd deps/{s} && git submodule update --init --recursive", .{dep_name}),
        }) catch unreachable;
    }
    return args.toOwnedSlice(b.allocator) catch unreachable;
}

fn needsSubmoduleInit(dep_name: []const u8) bool {
    return std.mem.eql(u8, dep_name, "mbedtls");
}

fn normalizeGitUrl(b: *std.Build, url: []const u8) []const u8 {
    return normalizeGitUrlFromAllocator(b.allocator, url);
}

fn normalizeGitUrlFromAllocator(allocator: std.mem.Allocator, url: []const u8) []const u8 {
    _ = allocator;
    return url;
}

fn buildDefaultCMakeArgs(b: *std.Build, dep_name: []const u8, user_args: []const []const u8) []const []const u8 {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    if (std.mem.eql(u8, dep_name, "juce")) {
        args.appendSlice(b.allocator, &.{
            "-DJUCE_BUILD_EXAMPLES=OFF",
            "-DJUCE_BUILD_EXTRAS=OFF",
            "-DJUCE_MODULES_ONLY=ON",
            "-DJUCE_GENERATE_JUCE_HEADER=ON",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "json")) {
        args.appendSlice(b.allocator, &.{
            "-DJSON_BuildTests=OFF",
            "-DJSON_Install=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "fmt")) {
        args.appendSlice(b.allocator, &.{
            "-DFMT_DOC=OFF",
            "-DFMT_TEST=OFF",
            "-DBUILD_SHARED_LIBS=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "spdlog")) {
        args.appendSlice(b.allocator, &.{
            "-DSPDLOG_BUILD_EXAMPLE=OFF",
            "-DSPDLOG_BUILD_TESTS=OFF",
            "-DSPDLOG_BUILD_BENCH=OFF",
            "-DBUILD_SHARED_LIBS=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "curl")) {
        args.appendSlice(b.allocator, &.{
            "-DBUILD_CURL_EXE=OFF",
            "-DBUILD_SHARED_LIBS=OFF",
            "-DBUILD_TESTING=OFF",
            "-DCURL_DISABLE_TESTS=ON",
            // Optional dependencies curl autodetects from the host. Left on,
            // curl compiles against whatever happens to be installed while the
            // link line does not carry it, so the build succeeds or fails
            // depending on the machine. Disabled to keep it hermetic.
            "-DCURL_USE_LIBPSL=OFF",
            "-DCURL_USE_LIBSSH2=OFF",
            "-DCURL_USE_LIBSSH=OFF",
            "-DCURL_BROTLI=OFF",
            "-DCURL_ZSTD=OFF",
            "-DUSE_NGHTTP2=OFF",
            "-DUSE_LIBIDN2=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "zlib")) {
        args.appendSlice(b.allocator, &.{
            "-DBUILD_SHARED_LIBS=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "mbedtls")) {
        args.appendSlice(b.allocator, &.{
            "-DENABLE_PROGRAMS=OFF",
            "-DENABLE_TESTING=OFF",
            "-DMBEDTLS_BUILD_SHARED_LIBS=OFF",
            "-DMBEDTLS_FATAL_WARNINGS=OFF",
            "-DUSE_STATIC_MBEDTLS_LIBRARY=ON",
            "-DUSE_SHARED_MBEDTLS_LIBRARY=OFF",
        }) catch unreachable;
    }
    args.appendSlice(b.allocator, user_args) catch unreachable;
    return args.toOwnedSlice(b.allocator) catch unreachable;
}

fn chooseCMakeGenerator(b: *std.Build) ?[]const u8 {
    const env_gen = zaza_cmd.envString(b, "CMAKE_GENERATOR");
    if (env_gen) |gen| return gen;
    return null;
}

fn chooseCMakeToolchain(b: *std.Build) ?[]const u8 {
    const env_toolchain = zaza_cmd.envString(b, "CMAKE_TOOLCHAIN_FILE");
    if (env_toolchain) |path| return path;
    return null;
}

fn makeCMakeConfigureCommand(
    b: *std.Build,
    source_dir: []const u8,
    build_dir: []const u8,
    config_name: []const u8,
    generator: ?[]const u8,
    toolchain_file: ?[]const u8,
    install_prefix: ?[]const u8,
    extra_args: []const []const u8,
) []const []const u8 {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    args.appendSlice(b.allocator, &.{ "cmake", "-S", source_dir, "-B", build_dir }) catch unreachable;
    if (generator orelse chooseCMakeGenerator(b)) |gen| {
        args.appendSlice(b.allocator, &.{ "-G", gen }) catch unreachable;
    }
    args.append(b.allocator, b.fmt("-DCMAKE_BUILD_TYPE={s}", .{config_name})) catch unreachable;
    if (toolchain_file orelse chooseCMakeToolchain(b)) |toolchain| {
        args.append(b.allocator, b.fmt("-DCMAKE_TOOLCHAIN_FILE={s}", .{toolchain})) catch unreachable;
    }
    if (install_prefix) |prefix| {
        args.append(b.allocator, b.fmt("-DCMAKE_INSTALL_PREFIX={s}", .{prefix})) catch unreachable;
    }
    if (!hasCMakeFlag(extra_args, "CMAKE_EXPORT_COMPILE_COMMANDS")) {
        args.append(b.allocator, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON") catch unreachable;
    }
    args.appendSlice(b.allocator, extra_args) catch unreachable;
    return args.toOwnedSlice(b.allocator) catch unreachable;
}

fn makeCMakeBuildCommand(
    b: *std.Build,
    build_dir: []const u8,
    config_name: []const u8,
    extra_args: []const []const u8,
) []const []const u8 {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    args.appendSlice(b.allocator, &.{ "cmake", "--build", build_dir, "--config", config_name }) catch unreachable;
    args.appendSlice(b.allocator, extra_args) catch unreachable;
    return args.toOwnedSlice(b.allocator) catch unreachable;
}

fn makeCMakeInstallCommand(
    b: *std.Build,
    build_dir: []const u8,
    config_name: []const u8,
    install_prefix: ?[]const u8,
    extra_args: []const []const u8,
) []const []const u8 {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    args.appendSlice(b.allocator, &.{ "cmake", "--install", build_dir, "--config", config_name }) catch unreachable;
    if (install_prefix) |prefix| {
        args.appendSlice(b.allocator, &.{ "--prefix", prefix }) catch unreachable;
    }
    args.appendSlice(b.allocator, extra_args) catch unreachable;
    return args.toOwnedSlice(b.allocator) catch unreachable;
}

/// Predefined build configurations
pub const Configs = struct {
    pub const Debug = BuildConfig{
        .mode = .Debug,
        .defines = &.{"DEBUG=1"},
    };

    pub const Release = BuildConfig{
        .mode = .Release,
        .defines = &.{"NDEBUG=1"},
    };

    pub const RelWithDebInfo = BuildConfig{
        .mode = .RelWithDebInfo,
        .defines = &.{ "DEBUG=1", "NDEBUG=1" },
    };

    pub const MinSizeRel = BuildConfig{
        .mode = .MinSizeRel,
        .defines = &.{"NDEBUG=1"},
    };
};

/// A C or C++ build target: an executable or a library. It is a plain struct,
/// so a target is data you can inspect, serialise, and modify before building
/// it. Construct one through a kind constructor (`executable`, `staticLibrary`,
/// `sharedLibrary`, `objectLibrary`, `interfaceLibrary`) and build it with
/// `build` or `buildWithTarget`. The public API re-exports this as `Target`.
pub const CppExample = struct {
    name: []const u8,
    description: []const u8,
    kind: TargetKind = .executable,
    source_files: []const []const u8,
    include_dirs: []const []const u8,
    public_include_dirs: []const []const u8 = &.{},
    private_include_dirs: []const []const u8 = &.{},
    cpp_flags: []const []const u8,
    public_defines: []const []const u8 = &.{},
    private_defines: []const []const u8 = &.{},
    public_link_libs: []const []const u8 = &.{},
    private_link_libs: []const []const u8 = &.{},
    install_headers: []const []const u8 = &.{},
    install_libs: []const []const u8 = &.{},
    artifact_copies: []const ArtifactCopy = &.{},
    file_copies: []const FileCopy = &.{},
    export_cmake: bool = false,
    export_name: ?[]const u8 = null,
    generated_source_files: []const []const u8 = &.{},
    custom_commands: []const CustomCommand = &.{},
    post_build_commands: []const CustomCommand = &.{},
    deps: []const Dependency,
    configs: []const BuildConfig,
    deps_build_system: BuildSystem,
    main_build_system: BuildSystem,
    cpp_std: ?[]const u8,
    c_std: ?[]const u8 = null,
    cmake_config: ?CMakeConfig = null,
    enable_system_commands: bool = false,

    /// Build a target of the given kind from `options`. The five kind
    /// constructors below call this; use one of them rather than `make`.
    pub fn make(kind: TargetKind, options: TargetOptions) CppExample {
        return .{
            .name = options.name,
            .description = options.description orelse options.name,
            .kind = kind,
            .source_files = options.source_files,
            .include_dirs = options.include_dirs,
            .public_include_dirs = options.public_include_dirs,
            .private_include_dirs = options.private_include_dirs,
            .cpp_flags = options.cpp_flags,
            .public_defines = options.public_defines,
            .private_defines = options.private_defines,
            .public_link_libs = options.public_link_libs,
            .private_link_libs = options.private_link_libs,
            .install_headers = options.install_headers,
            .install_libs = options.install_libs,
            .artifact_copies = options.artifact_copies,
            .file_copies = options.file_copies,
            .export_cmake = options.export_cmake,
            .export_name = options.export_name,
            .generated_source_files = options.generated_source_files,
            .custom_commands = options.custom_commands,
            .post_build_commands = options.post_build_commands,
            .deps = options.deps,
            .configs = options.configs orelse BuildConfigs.debug_only,
            .deps_build_system = options.deps_build_system,
            .main_build_system = options.main_build_system,
            .cpp_std = options.cpp_std,
            .c_std = options.c_std,
            .cmake_config = options.cmake_config,
            .enable_system_commands = options.enable_system_commands,
        };
    }

    /// An executable target.
    pub fn executable(options: TargetOptions) CppExample {
        return make(.executable, options);
    }

    /// A static library (`.a` / `.lib`).
    pub fn staticLibrary(options: TargetOptions) CppExample {
        return make(.static_library, options);
    }

    /// A shared library (`.so` / `.dylib` / `.dll`).
    pub fn sharedLibrary(options: TargetOptions) CppExample {
        return make(.shared_library, options);
    }

    /// An object library: compiled objects with no final link.
    pub fn objectLibrary(options: TargetOptions) CppExample {
        return make(.object_library, options);
    }

    /// An interface library: usage requirements only, nothing compiled.
    pub fn interfaceLibrary(options: TargetOptions) CppExample {
        return make(.interface_library, options);
    }

    pub fn deinit(self: CppExample, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        for (self.source_files) |src| {
            allocator.free(src);
        }
        allocator.free(self.source_files);
        for (self.include_dirs) |dir| {
            allocator.free(dir);
        }
        allocator.free(self.include_dirs);
        for (self.cpp_flags) |flag| {
            allocator.free(flag);
        }
        allocator.free(self.cpp_flags);
        for (self.generated_source_files) |src| {
            allocator.free(src);
        }
        allocator.free(self.generated_source_files);
        for (self.artifact_copies) |copy| {
            allocator.free(copy.dest_dir);
            if (copy.step_name) |name| allocator.free(name);
        }
        allocator.free(self.artifact_copies);
        for (self.file_copies) |copy| {
            allocator.free(copy.source_path);
            allocator.free(copy.dest_path);
            if (copy.step_name) |name| allocator.free(name);
        }
        allocator.free(self.file_copies);
        for (self.custom_commands) |cmd| {
            allocator.free(cmd.name);
            for (cmd.argv) |arg| allocator.free(arg);
            allocator.free(cmd.argv);
        }
        allocator.free(self.custom_commands);
        for (self.post_build_commands) |cmd| {
            allocator.free(cmd.name);
            for (cmd.argv) |arg| allocator.free(arg);
            allocator.free(cmd.argv);
        }
        allocator.free(self.post_build_commands);
        for (self.deps) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.url);
            if (dep.git_ref) |git_ref| allocator.free(git_ref);
            if (dep.include_path) |path| {
                allocator.free(path);
            }
            for (dep.build_command) |cmd| {
                allocator.free(cmd);
            }
            allocator.free(dep.build_command);
        }
        allocator.free(self.deps);
        if (self.cpp_std) |std_ver| {
            allocator.free(std_ver);
        }
    }

    /// Helper for CMake generation
    const cmake = struct {
        fn write(gpa: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), comptime fmt: []const u8, args: anytype) !void {
            try listPrint(writer, gpa, fmt ++ "\n", args);
        }

        fn section(gpa: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), name: []const u8, args: []const []const u8) !void {
            try listPrint(writer, gpa, "{s}(", .{name});
            for (args, 0..) |arg, i| {
                if (i > 0) try writer.appendSlice(gpa, " ");
                try writer.appendSlice(gpa, arg);
            }
            try writer.appendSlice(gpa, ")\n");
        }

        fn list(gpa: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), name: []const u8, target: []const u8, items: []const []const u8) !void {
            try listScoped(gpa, writer, name, target, "PRIVATE", items);
        }

        fn listScoped(gpa: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), name: []const u8, target: []const u8, scope: []const u8, items: []const []const u8) !void {
            try listPrint(writer, gpa, "{s}({s} {s}\n", .{ name, target, scope });
            for (items) |item| {
                try listPrint(writer, gpa, "    {s}\n", .{item});
            }
            try writer.appendSlice(gpa, ")\n\n");
        }
    };

    pub fn getExeName(self: CppExample, b: *std.Build, config: BuildConfig) []const u8 {
        return b.fmt("{s}_{s}", .{ self.name, config.mode.toCMakeString() });
    }

    pub fn targetName(self: CppExample) []const u8 {
        return self.name;
    }

    pub fn allSourceFiles(self: CppExample, allocator: std.mem.Allocator) ![]const []const u8 {
        return concatSlices(allocator, self.source_files, self.generated_source_files);
    }

    pub fn generateCMake(self: CppExample, b: *std.Build) !void {
        var writer: std.ArrayListUnmanaged(u8) = .empty;
        defer writer.deinit(b.allocator);

        // Header
        try cmake.write(b.allocator, &writer, "cmake_minimum_required(VERSION 3.15)", .{});
        try cmake.write(b.allocator, &writer, "", .{});
        try cmake.section(b.allocator, &writer, "project", &.{self.name});
        try cmake.write(b.allocator, &writer, "", .{});

        // Add dependencies
        for (self.deps) |dep| {
            try cmake.write(b.allocator, &writer, "add_subdirectory(deps/{s})", .{dep.name});
        }
        try cmake.write(b.allocator, &writer, "", .{});

        // Create target
        switch (self.kind) {
            .executable => try cmake.write(b.allocator, &writer, "add_executable({s}", .{self.name}),
            .static_library => try cmake.write(b.allocator, &writer, "add_library({s} STATIC", .{self.name}),
            .shared_library => try cmake.write(b.allocator, &writer, "add_library({s} SHARED", .{self.name}),
            .object_library => try cmake.write(b.allocator, &writer, "add_library({s} OBJECT", .{self.name}),
            .interface_library => try cmake.write(b.allocator, &writer, "add_library({s} INTERFACE)", .{self.name}),
        }
        if (self.kind != .interface_library) {
            for (self.source_files) |src| {
                try cmake.write(b.allocator, &writer, "    {s}", .{src});
            }
            try cmake.write(b.allocator, &writer, ")", .{});
        }
        try cmake.write(b.allocator, &writer, "", .{});

        // Include directories
        if (self.public_include_dirs.len > 0) {
            try cmake.listScoped(b.allocator, &writer, "target_include_directories", self.name, "PUBLIC", self.public_include_dirs);
        }
        if (self.include_dirs.len > 0 or self.private_include_dirs.len > 0) {
            var all_private: std.ArrayListUnmanaged([]const u8) = .empty;
            defer all_private.deinit(b.allocator);
            try all_private.appendSlice(b.allocator, self.include_dirs);
            try all_private.appendSlice(b.allocator, self.private_include_dirs);
            if (all_private.items.len > 0) {
                try cmake.listScoped(b.allocator, &writer, "target_include_directories", self.name, "PRIVATE", all_private.items);
            }
        }

        // Compiler flags
        var flags: std.ArrayListUnmanaged([]const u8) = .empty;
        defer flags.deinit(b.allocator);

        // Add the language standard: C when c_std is set, else C++.
        const std_flag = if (self.c_std) |c_std|
            try std.fmt.allocPrint(b.allocator, "-std=c{s}", .{c_std})
        else
            try std.fmt.allocPrint(b.allocator, "-std=c++{s}", .{self.cpp_std orelse "17"});
        try flags.append(b.allocator, std_flag);

        // Add other flags
        try flags.appendSlice(b.allocator, self.cpp_flags);

        try cmake.list(b.allocator, &writer, "target_compile_options", self.name, flags.items);

        // Compile definitions
        if (self.public_defines.len > 0) {
            try cmake.listScoped(b.allocator, &writer, "target_compile_definitions", self.name, "PUBLIC", self.public_defines);
        }
        if (self.private_defines.len > 0) {
            try cmake.listScoped(b.allocator, &writer, "target_compile_definitions", self.name, "PRIVATE", self.private_defines);
        }

        // Link libraries
        if (self.public_link_libs.len > 0) {
            try cmake.listScoped(b.allocator, &writer, "target_link_libraries", self.name, "PUBLIC", self.public_link_libs);
        }
        if (self.private_link_libs.len > 0) {
            try cmake.listScoped(b.allocator, &writer, "target_link_libraries", self.name, "PRIVATE", self.private_link_libs);
        }

        // Write CMakeLists.txt
        try writeBuildRootFile(b, "CMakeLists.txt", writer.items);
    }

    /// Build the target for the standard target the user selected on the
    /// command line, and return the final compile step. This is the usual entry
    /// point from a build file.
    pub fn build(self: CppExample, b: *std.Build) !*std.Build.Step.Compile {
        const target = b.standardTargetOptions(.{});
        return self.buildWithTarget(b, target);
    }

    /// The exact C++ flag set applied to every source in a config. Shared so
    /// the Zig build path and the zaza-drive manifest cannot drift: both must
    /// compile with identical flags or they build different programs.
    fn cppCompileFlags(
        self: CppExample,
        b: *std.Build,
        config: BuildConfig,
        config_name: []const u8,
        public_defines: []const []const u8,
        private_defines: []const []const u8,
    ) ![]const []const u8 {
        var list: std.ArrayListUnmanaged([]const u8) = .empty;
        try list.appendSlice(b.allocator, filterByConfig(b, self.cpp_flags, config_name));
        try list.appendSlice(b.allocator, config.cpp_flags);
        if (self.c_std) |c_std| {
            // C target: a C standard and none of the C++-only flags.
            try list.append(b.allocator, try std.fmt.allocPrint(b.allocator, "-std=c{s}", .{c_std}));
        } else {
            try list.append(b.allocator, try CppConfig.getStdFlag(b.allocator, self.cpp_std orelse CppConfig.std_version));
            try list.appendSlice(b.allocator, &.{ "-fexceptions", "-frtti", "-D_HAS_EXCEPTIONS=1" });
        }
        for (public_defines) |def| try list.append(b.allocator, ensureDefineFlag(b, def));
        for (private_defines) |def| try list.append(b.allocator, ensureDefineFlag(b, def));
        for (config.defines) |def| try list.append(b.allocator, ensureDefineFlag(b, def));
        return list.toOwnedSlice(b.allocator);
    }

    /// Emit a zaza-drive manifest for the first configured mode. The driver in
    /// tools/zaza-drive reads this to build the same target without the Zig
    /// build runner on the hot path. The compile flags come from the same
    /// cppCompileFlags used by buildWithTarget.
    ///
    /// When `native` is false the compiler is `zig c++`, matching what
    /// buildWithTarget uses, so the fast path compiles identically to the normal
    /// build. When `native` is true the compiler is the system `c++`, which
    /// starts about twice as fast as the zig wrapper and roughly halves an
    /// incremental rebuild. That is a different compiler from the canonical
    /// build, so it is a fast iteration path, and release or cross builds should
    /// still go through `zig build`.
    pub fn writeDriveManifest(self: CppExample, b: *std.Build, native: bool) ![]const u8 {
        const config = if (self.configs.len > 0) self.configs[0] else BuildConfig{ .mode = .Debug };
        const config_name = config.mode.toCMakeString();

        const public_defines = filterByConfig(b, self.public_defines, config_name);
        const private_defines = filterByConfig(b, self.private_defines, config_name);
        const flags = try self.cppCompileFlags(b, config, config_name, public_defines, private_defines);

        // Built with appends and b.fmt rather than an ArrayList writer, which
        // 0.16 removed for unmanaged lists.
        var out: std.ArrayListUnmanaged(u8) = .empty;

        if (native) {
            // The system default C++ compiler: clang++ on macOS, usually g++ or
            // clang++ on Linux. Lower per-invocation startup than the zig wrapper.
            try out.appendSlice(b.allocator, "compiler c++\n");
        } else {
            // The same zig binary running this build, in c++ mode.
            try out.appendSlice(b.allocator, b.fmt("compiler {s} c++\n", .{b.graph.zig_exe}));
        }

        // cflags = the shared compile flags, plus -I for each include dir.
        try out.appendSlice(b.allocator, "cflags");
        for (flags) |f| try out.appendSlice(b.allocator, b.fmt(" {s}", .{f}));
        for (self.public_include_dirs) |dir| try out.appendSlice(b.allocator, b.fmt(" -I{s}", .{dir}));
        for (self.include_dirs) |dir| try out.appendSlice(b.allocator, b.fmt(" -I{s}", .{dir}));
        try out.appendSlice(b.allocator, "\n");

        // Separate object dir per compiler: zig-compiled and system-compiled
        // objects are not interchangeable, so they must not share a cache.
        try out.appendSlice(b.allocator, if (native) "outdir .zaza-drive-native\n" else "outdir .zaza-drive\n");
        try out.appendSlice(b.allocator, b.fmt("bin {s}\n", .{self.name}));

        for (try self.allSourceFiles(b.allocator)) |src| {
            try out.appendSlice(b.allocator, b.fmt("src {s}\n", .{src}));
        }
        return out.toOwnedSlice(b.allocator);
    }

    /// Build the target for a specific resolved target and return the final
    /// compile step. Use this when the caller chooses the target rather than the
    /// command line, for example when cross-compiling in a fixed configuration.
    pub fn buildWithTarget(self: CppExample, b: *std.Build, target: std.Build.ResolvedTarget) !*std.Build.Step.Compile {
        if (target.result.os.tag == .windows and target.result.abi == .msvc and self.main_build_system == .Zig) {
            @panic("Zig 0.14 cannot compile C++ with the MSVC ABI (see Zig issue #18685). " ++ "Use ZAZA_WINDOWS_TOOLCHAIN=gnu or ZAZA_TARGET=x86_64-windows-gnu, " ++ "or switch this example to a system toolchain (CMake).");
        }
        // Generate CMakeLists.txt first
        try self.generateCMake(b);

        // Print build information (disabled in build runner to avoid crashes)

        var last_exe: ?*std.Build.Step.Compile = null;
        var final_steps: std.ArrayListUnmanaged(*std.Build.Step) = .empty;
        defer final_steps.deinit(b.allocator);

        // For each configuration
        for (self.configs) |config| {
            const config_name = config.mode.toCMakeString();

            var last_step: ?*std.Build.Step = null;

            // Clone and build dependencies (optional)
            if (self.enable_system_commands) {
                for (self.deps) |dep| {
                    // Clone step
                    const clone_step = zaza_cmd.addCommandStep(
                        b,
                        b.fmt("clone_{s}_{s}", .{ dep.name, config_name }),
                        makeCloneCommand(b, dep),
                    );
                    if (last_step) |prev| {
                        clone_step.dependencies.append(prev) catch unreachable;
                    }
                    last_step = clone_step;

                    // Submodule init step (for deps that need it)
                    if (needsSubmoduleInit(dep.name)) {
                        const submodule_step = zaza_cmd.addCommandStep(
                            b,
                            b.fmt("submodule_init_{s}_{s}", .{ dep.name, config_name }),
                            makeSubmoduleInitCommand(b, dep.name),
                        );
                        if (last_step) |prev| {
                            submodule_step.dependencies.append(prev) catch unreachable;
                        }
                        last_step = submodule_step;
                    }

                    // Build step (only after clone completes)
                    const dep_build_system = dep.type orelse self.deps_build_system;
                    if (dep_build_system == .CMake) {
                        const cmake_cfg = dep.cmake_config orelse CMakeConfig{};
                        const dep_source_dir = cmake_cfg.source_dir orelse b.pathJoin(&.{ "deps", dep.name });
                        const dep_build_dir = cmake_cfg.build_dir orelse b.pathJoin(&.{ "deps", dep.name, "build", config_name });
                        const extra_configure_args = buildDefaultCMakeArgs(b, dep.name, cmake_cfg.configure_args);

                        const configure_step = zaza_cmd.addCommandStep(b, b.fmt("configure_{s}_{s}", .{ dep.name, config_name }), makeCMakeConfigureCommand(
                            b,
                            dep_source_dir,
                            dep_build_dir,
                            config_name,
                            cmake_cfg.generator,
                            cmake_cfg.toolchain_file,
                            cmake_cfg.install_prefix,
                            extra_configure_args,
                        ));
                        if (last_step) |prev| {
                            configure_step.dependencies.append(prev) catch unreachable;
                        }
                        last_step = configure_step;

                        const build_step = zaza_cmd.addCommandStep(b, b.fmt("build_{s}_{s}", .{ dep.name, config_name }), makeCMakeBuildCommand(
                            b,
                            dep_build_dir,
                            config_name,
                            cmake_cfg.build_args,
                        ));
                        build_step.dependencies.append(configure_step) catch unreachable;
                        last_step = build_step;
                        if (cmake_cfg.install) {
                            const install_step = zaza_cmd.addCommandStep(b, b.fmt("install_{s}_{s}", .{ dep.name, config_name }), makeCMakeInstallCommand(
                                b,
                                dep_build_dir,
                                config_name,
                                cmake_cfg.install_prefix,
                                cmake_cfg.install_args,
                            ));
                            install_step.dependencies.append(build_step) catch unreachable;
                            last_step = install_step;
                        }
                    } else if (dep.build_command.len > 0) {
                        const cmd_step = zaza_cmd.addCommandStep(
                            b,
                            b.fmt("build_{s}_{s}", .{ dep.name, config_name }),
                            dep.build_command,
                        );
                        if (last_step) |prev| {
                            cmd_step.dependencies.append(prev) catch unreachable;
                        }
                        last_step = cmd_step;
                    }
                }
            }
            if (self.custom_commands.len > 0) {
                if (!self.enable_system_commands) {
                    std.log.err(
                        "target '{s}': custom command '{s}' needs system commands, which are disabled. " ++
                            "Enable with -Dsystem-cmds=true or ZAZA_SYSTEM_CMDS=1.",
                        .{ self.name, self.custom_commands[0].name },
                    );
                    return error.SystemCommandsDisabled;
                }
                for (self.custom_commands) |cmd| {
                    const custom_step = zaza_cmd.addCommandStep(
                        b,
                        b.fmt("{s}_{s}", .{ cmd.name, config_name }),
                        cmd.argv,
                    );
                    if (last_step) |prev| {
                        custom_step.dependencies.append(prev) catch unreachable;
                    }
                    last_step = custom_step;
                }
            }

            // Build main project with selected build system
            if (self.main_build_system == .CMake) {
                if (!self.enable_system_commands) {
                    std.log.err(
                        "target '{s}': CMake main-build phase needs system commands, which are disabled. " ++
                            "Enable with -Dsystem-cmds=true or ZAZA_SYSTEM_CMDS=1.",
                        .{self.name},
                    );
                    return error.SystemCommandsDisabled;
                }
                if (self.artifact_copies.len > 0) return error.ArtifactCopyRequiresZigArtifact;
                // Use CMake for main project
                const cmake_cfg = self.cmake_config orelse CMakeConfig{};
                const source_dir = cmake_cfg.source_dir orelse ".";
                const build_dir = cmake_cfg.build_dir orelse b.pathJoin(&.{ "build", config_name });
                const cmake_configure = zaza_cmd.addCommandStep(b, b.fmt("configure_{s}_{s}", .{ self.name, config_name }), makeCMakeConfigureCommand(
                    b,
                    source_dir,
                    build_dir,
                    config_name,
                    cmake_cfg.generator,
                    cmake_cfg.toolchain_file,
                    cmake_cfg.install_prefix,
                    cmake_cfg.configure_args,
                ));
                if (last_step) |prev| cmake_configure.dependencies.append(prev) catch unreachable;

                const cmake_build = zaza_cmd.addCommandStep(b, b.fmt("build_{s}_{s}", .{ self.name, config_name }), makeCMakeBuildCommand(
                    b,
                    build_dir,
                    config_name,
                    cmake_cfg.build_args,
                ));
                cmake_build.dependencies.append(cmake_configure) catch unreachable;
                last_step = cmake_build;
                if (cmake_cfg.install) {
                    const cmake_install = zaza_cmd.addCommandStep(b, b.fmt("install_{s}_{s}", .{ self.name, config_name }), makeCMakeInstallCommand(
                        b,
                        build_dir,
                        config_name,
                        cmake_cfg.install_prefix,
                        cmake_cfg.install_args,
                    ));
                    cmake_install.dependencies.append(cmake_build) catch unreachable;
                    last_step = cmake_install;
                }
                if (last_step) |step| {
                    if (addFileCopies(
                        b,
                        b.fmt("{s}-{s}", .{ self.name, config_name }),
                        self.file_copies,
                        step,
                    )) |copy_step| {
                        last_step = copy_step;
                    }
                }
                if (last_step) |step| {
                    if (try addPostBuildCommands(b, self, config_name, step)) |post_step| {
                        last_step = post_step;
                    }
                }
                if (last_step) |step| {
                    final_steps.append(b.allocator, step) catch unreachable;
                }
                try emitInstallAndExport(b, self, config_name);
                const manifest = try buildToolingManifest(
                    b.allocator,
                    self,
                    config,
                    config_name,
                    b.pathJoin(&.{ "deps", "compile_commands", b.fmt("{s}.json", .{self.name}) }),
                    self.public_include_dirs,
                    self.private_include_dirs,
                    self.include_dirs,
                    self.public_defines,
                    self.private_defines,
                );
                defer b.allocator.free(manifest);
                const write_files = b.addWriteFiles();
                const manifest_rel = b.fmt("share/zaza/{s}-{s}-tooling.json", .{ self.name, config_name });
                const manifest_file = write_files.add(manifest_rel, manifest);
                _ = b.addInstallFileWithDir(manifest_file, .prefix, manifest_rel);
                continue;
            } else {
                // Build with Zig directly since json is header-only
                const public_include_dirs = filterByConfig(b, self.public_include_dirs, config_name);
                const private_include_dirs = filterByConfig(b, self.private_include_dirs, config_name);
                const include_dirs = filterByConfig(b, self.include_dirs, config_name);
                const public_defines = filterByConfig(b, self.public_defines, config_name);
                const private_defines = filterByConfig(b, self.private_defines, config_name);
                const public_link_libs = filterByConfig(b, self.public_link_libs, config_name);
                const private_link_libs = filterByConfig(b, self.private_link_libs, config_name);

                const compile = try addTargetArtifact(b, self, config, target);

                // Add source files with the shared C++ flag set.
                const cpp_flags = try self.cppCompileFlags(b, config, config_name, public_defines, private_defines);

                const all_sources = try self.allSourceFiles(b.allocator);
                if (self.kind != .interface_library) {
                    compile.root_module.addCSourceFiles(.{
                        .files = all_sources,
                        .flags = cpp_flags,
                    });
                }

                // Add include directories
                for (public_include_dirs) |dir| {
                    compile.root_module.addIncludePath(.{ .cwd_relative = dir });
                }
                for (include_dirs) |dir| {
                    compile.root_module.addIncludePath(.{ .cwd_relative = dir });
                }
                for (private_include_dirs) |dir| {
                    compile.root_module.addIncludePath(.{ .cwd_relative = dir });
                }
                // Add system include directories from build config
                for (config.system_includes) |dir| {
                    compile.root_module.addSystemIncludePath(.{ .cwd_relative = dir });
                }
                // Add include directories from Zig package deps
                for (self.deps) |dep| {
                    if (dep.pkg_name) |pkg_name| {
                        // Manifest dependencies are lazy, so they are fetched
                        // only when a target actually consumes them. A null
                        // return means the fetch is pending; the build runner
                        // re-invokes once it is available.
                        if (b.lazyDependency(pkg_name, .{})) |pkg| {
                            const include_subdir = dep.pkg_include orelse ".";
                            compile.root_module.addIncludePath(pkg.path(include_subdir));
                        }
                    }
                }

                // Link the C or C++ runtime.
                if (self.kind != .object_library and self.kind != .interface_library) {
                    if (self.c_std != null) {
                        compile.root_module.link_libc = true;
                    } else {
                        compile.root_module.link_libcpp = true;
                    }
                }

                // Link extra libraries from build config
                for (config.link_paths) |lib_path| {
                    compile.root_module.addLibraryPath(.{ .cwd_relative = lib_path });
                }
                for (config.link_files) |lib_file| {
                    compile.root_module.addObjectFile(.{ .cwd_relative = lib_file });
                }
                for (config.link_frameworks) |framework| {
                    compile.root_module.linkFramework(framework, .{});
                }
                for (config.link_libs) |lib| {
                    compile.root_module.linkSystemLibrary(lib, .{});
                }
                for (public_link_libs) |lib| {
                    compile.root_module.linkSystemLibrary(lib, .{});
                }
                for (private_link_libs) |lib| {
                    compile.root_module.linkSystemLibrary(lib, .{});
                }

                // Optional: compile_commands.json for Zig builds
                try emitCompileCommands(b, self, config, config_name, public_include_dirs, private_include_dirs, include_dirs, public_defines, private_defines);

                // Optional install + export
                try emitInstallAndExport(b, self, config_name);

                if (last_step) |prev| {
                    compile.step.dependencies.append(prev) catch unreachable;
                }
                last_step = &compile.step;
                if (addArtifactCopies(
                    b,
                    b.fmt("{s}-{s}", .{ self.name, config_name }),
                    compile,
                    self.artifact_copies,
                    last_step,
                )) |copy_step| {
                    last_step = copy_step;
                }
                if (addFileCopies(
                    b,
                    b.fmt("{s}-{s}", .{ self.name, config_name }),
                    self.file_copies,
                    last_step,
                )) |copy_step| {
                    last_step = copy_step;
                }
                if (try addPostBuildCommands(b, self, config_name, last_step)) |post_step| {
                    last_step = post_step;
                }
                last_exe = compile;
            }

            if (last_step) |step| {
                final_steps.append(b.allocator, step) catch unreachable;
            }
        }

        for (final_steps.items) |step| {
            b.getInstallStep().dependOn(step);
        }

        return last_exe orelse return error.NoExecutableBuilt;
    }
};

pub const JUCEApplication = struct {
    const Self = @This();

    pub const BuilderOptions = struct {
        enable_system_commands: bool = false,
    };

    // Configuration struct for JUCE applications
    pub const JuceConfig = struct {
        /// The name of your application
        name: []const u8,
        /// A brief description of what your app does
        description: []const u8,
        /// The version number (e.g. "1.0.0")
        version: []const u8,
        /// Your company name
        company: []const u8,
        /// The build mode (Debug/Release/etc)
        build_mode: BuildMode,
        /// Source files to compile (e.g. "src/main.cpp")
        sources: []const []const u8 = &.{},
        /// JUCE modules to link (e.g. "juce_core")
        modules: []const []const u8 = &.{},
        /// C++ standard version (e.g. "17", "20")
        cpp_std: ?[]const u8 = null,
        /// Subdirectory for generated CMakeLists (default: ".")
        cmake_root: []const u8 = ".",
        /// JUCE git tag/branch (e.g. "8.0.14", "8.0.12", "master")
        juce_git_tag: ?[]const u8 = null,
    };

    // Common JUCE modules that most apps need
    const common_modules = [_][]const u8{
        "juce_core",
        "juce_data_structures",
        "juce_events",
        "juce_graphics",
        "juce_gui_basics",
    };

    // CMake file generation helpers
    const cmake = struct {
        fn write(gpa: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), comptime fmt: []const u8, args: anytype) !void {
            try listPrint(writer, gpa, fmt ++ "\n", args);
        }

        fn section(gpa: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), name: []const u8, args: []const []const u8) !void {
            try listPrint(writer, gpa, "{s}(", .{name});
            for (args, 0..) |arg, i| {
                if (i > 0) try writer.appendSlice(gpa, " ");
                try writer.appendSlice(gpa, arg);
            }
            try writer.appendSlice(gpa, ")\n");
        }

        fn list(gpa: std.mem.Allocator, writer: *std.ArrayListUnmanaged(u8), name: []const u8, target: []const u8, items: []const []const u8) !void {
            try listPrint(writer, gpa, "{s}({s} PRIVATE\n", .{ name, target });
            for (items) |item| {
                try listPrint(writer, gpa, "    {s}\n", .{item});
            }
            try writer.appendSlice(gpa, ")\n\n");
        }
    };

    // Template for JUCE GUI apps
    pub fn template(comptime config: JuceConfig) type {
        return struct {
            pub fn build(b: *std.Build) !void {
                var app = JUCEApplication.builder(b);
                defer app.deinit();

                const app_builder = try app.configure(config);
                const example = try app_builder.build(.{});
                _ = try example.build(b);
            }

            pub fn buildWithTarget(b: *std.Build, target: std.Build.ResolvedTarget) !void {
                var app = JUCEApplication.builder(b);
                defer app.deinit();

                const app_builder = try app.configure(config);
                const example = try app_builder.build(.{});
                _ = try example.buildWithTarget(b, target);
            }
        };
    }

    const Builder = struct {
        b: *std.Build,
        name: []const u8 = "",
        description: []const u8 = "",
        version: []const u8 = "1.0.0",
        company: []const u8 = "",
        sources: std.ArrayListUnmanaged([]const u8),
        modules: std.ArrayListUnmanaged([]const u8),
        build_mode: BuildMode = .Debug,
        cpp_std: ?[]const u8 = null,
        cmake_root: []const u8 = ".",
        juce_git_tag: ?[]const u8 = null,

        pub fn init(b: *std.Build) Builder {
            return .{
                .b = b,
                .sources = .empty,
                .modules = .empty,
            };
        }

        pub fn deinit(self: *Builder) void {
            self.sources.deinit(self.b.allocator);
            self.modules.deinit(self.b.allocator);
        }

        pub fn configure(self: *Builder, config: JuceConfig) !*Builder {
            self.name = config.name;
            self.description = config.description;
            self.version = config.version;
            self.company = config.company;
            self.build_mode = config.build_mode;
            self.cpp_std = config.cpp_std;
            self.cmake_root = config.cmake_root;
            self.juce_git_tag = config.juce_git_tag;

            // Add sources and modules
            for (config.sources) |src| {
                try self.sources.append(self.b.allocator, src);
            }
            for (config.modules) |module| {
                try self.modules.append(self.b.allocator, module);
            }
            return self;
        }

        pub fn addSource(self: *Builder, source: []const u8) !*Builder {
            try self.sources.append(self.b.allocator, source);
            return self;
        }

        pub fn addModule(self: *Builder, module: []const u8) !*Builder {
            try self.modules.append(self.b.allocator, module);
            return self;
        }

        pub fn addCommonModules(self: *Builder) !*Builder {
            for (common_modules) |module| {
                try self.addModule(module);
            }
            return self;
        }

        pub fn setCppStd(self: *Builder, version: []const u8) *Builder {
            self.cpp_std = version;
            return self;
        }

        pub fn build(self: *Builder, options: BuilderOptions) !*CppExample {
            // Create CMakeLists.txt
            const writer = try self.b.allocator.create(std.ArrayListUnmanaged(u8));
            writer.* = .empty;
            defer writer.deinit(self.b.allocator);

            // Header
            try cmake.write(self.b.allocator, writer, "cmake_minimum_required(VERSION 3.22)", .{});
            try cmake.write(self.b.allocator, writer, "", .{});
            try cmake.section(self.b.allocator, writer, "project", &.{ self.name, "VERSION", self.version });
            try cmake.write(self.b.allocator, writer, "include(FetchContent)", .{});
            try cmake.write(self.b.allocator, writer, "set(FETCHCONTENT_QUIET OFF)", .{});
            try cmake.write(self.b.allocator, writer, "set(FETCHCONTENT_UPDATES_DISCONNECTED ON)", .{});
            try cmake.write(self.b.allocator, writer, "if (DEFINED JUCE_SOURCE_DIR)", .{});
            try cmake.write(self.b.allocator, writer, "    set(FETCHCONTENT_SOURCE_DIR_JUCE \"${{JUCE_SOURCE_DIR}}\")", .{});
            try cmake.write(self.b.allocator, writer, "elseif (EXISTS \"${{CMAKE_CURRENT_LIST_DIR}}/deps/juce/CMakeLists.txt\")", .{});
            try cmake.write(self.b.allocator, writer, "    set(FETCHCONTENT_SOURCE_DIR_JUCE \"${{CMAKE_CURRENT_LIST_DIR}}/deps/juce\")", .{});
            try cmake.write(self.b.allocator, writer, "endif()", .{});
            if (self.juce_git_tag) |tag| {
                try cmake.write(self.b.allocator, writer, "set(JUCE_GIT_TAG \"{s}\")", .{tag});
            } else {
                try cmake.write(self.b.allocator, writer, "if (NOT DEFINED JUCE_GIT_TAG)", .{});
                try cmake.write(self.b.allocator, writer, "    set(JUCE_GIT_TAG \"master\")", .{});
                try cmake.write(self.b.allocator, writer, "endif()", .{});
            }
            try cmake.write(self.b.allocator, writer, "FetchContent_Declare(juce", .{});
            try cmake.write(self.b.allocator, writer, "    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git", .{});
            try cmake.write(self.b.allocator, writer, "    GIT_TAG ${{JUCE_GIT_TAG}}", .{});
            try cmake.write(self.b.allocator, writer, ")", .{});
            try cmake.write(self.b.allocator, writer, "FetchContent_MakeAvailable(juce)", .{});
            try cmake.write(self.b.allocator, writer, "", .{});

            // App definition
            try cmake.write(self.b.allocator, writer, "juce_add_gui_app({s}", .{self.name});
            try cmake.write(self.b.allocator, writer, "    PRODUCT_NAME \"{s}\"", .{self.name});
            try cmake.write(self.b.allocator, writer, "    COMPANY_NAME \"{s}\"", .{self.company});
            try cmake.write(self.b.allocator, writer, "    VERSION \"{s}\"", .{self.version});
            try cmake.write(self.b.allocator, writer, ")", .{});
            try cmake.write(self.b.allocator, writer, "", .{});

            // Sources and modules
            try cmake.list(self.b.allocator, writer, "target_sources", self.name, self.sources.items);

            var juce_modules: std.ArrayListUnmanaged([]const u8) = .empty;
            defer juce_modules.deinit(self.b.allocator);
            for (self.modules.items) |module| {
                try juce_modules.append(self.b.allocator, try std.fmt.allocPrint(self.b.allocator, "juce::{s}", .{module}));
            }
            try cmake.list(self.b.allocator, writer, "target_link_libraries", self.name, juce_modules.items);

            // C++ standard
            try cmake.section(self.b.allocator, writer, "target_compile_features", &.{ self.name, "PRIVATE", "cxx_std_17" });

            // Write CMakeLists.txt
            const cmake_path = if (std.mem.eql(u8, self.cmake_root, "."))
                "CMakeLists.txt"
            else
                self.b.pathJoin(&.{ self.cmake_root, "CMakeLists.txt" });
            try writeBuildRootFile(self.b, cmake_path, writer.items);

            // Create CppExample
            const example = try self.b.allocator.create(CppExample);
            example.* = .{
                .name = self.name,
                .description = self.description,
                .source_files = try self.sources.toOwnedSlice(self.b.allocator),
                .include_dirs = &.{
                    "deps/juce/modules",
                    "build/JuceLibraryCode",
                },
                .cpp_flags = &.{"-std=c++17"},
                .deps = &.{},
                .configs = &.{
                    .{
                        .mode = self.build_mode,
                    },
                },
                .deps_build_system = .CMake,
                .main_build_system = .CMake,
                .cpp_std = self.cpp_std,
                .enable_system_commands = options.enable_system_commands,
                .cmake_config = .{
                    .source_dir = self.cmake_root,
                    .build_dir = self.b.pathJoin(&.{ self.cmake_root, "build" }),
                },
            };

            return example;
        }
    };

    pub fn builder(b: *std.Build) Builder {
        return Builder.init(b);
    }
};

fn addTargetArtifact(
    b: *std.Build,
    self: CppExample,
    config: BuildConfig,
    target: std.Build.ResolvedTarget,
) !*std.Build.Step.Compile {
    const optimize: std.builtin.OptimizeMode = switch (config.mode) {
        .Debug => .Debug,
        .Release => .ReleaseFast,
        .RelWithDebInfo => .ReleaseSafe,
        .MinSizeRel => .ReleaseSmall,
    };

    const compile = switch (self.kind) {
        .executable => b.addExecutable(.{
            .name = self.getExeName(b, config),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .root_source_file = null,
            }),
        }),
        .static_library => b.addLibrary(.{
            .name = self.getExeName(b, config),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .root_source_file = null,
            }),
            .linkage = .static,
        }),
        .shared_library => b.addLibrary(.{
            .name = self.getExeName(b, config),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .root_source_file = null,
            }),
            .linkage = .dynamic,
        }),
        .object_library => b.addObject(.{
            .name = self.getExeName(b, config),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .root_source_file = null,
            }),
        }),
        .interface_library => b.addLibrary(.{
            .name = self.getExeName(b, config),
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .root_source_file = null,
            }),
            .linkage = .static,
        }),
    };
    // 0.16 renamed the boolean want_lto to an LtoMode enum named lto.
    if (config.want_lto) {
        if (comptime @hasField(std.Build.Step.Compile, "want_lto")) {
            compile.want_lto = true;
        } else {
            compile.lto = .full;
        }
    }
    return compile;
}

fn filterByConfig(b: *std.Build, items: []const []const u8, config_name: []const u8) []const []const u8 {
    var out: std.ArrayListUnmanaged([]const u8) = .empty;
    for (items) |item| {
        if (std.mem.startsWith(u8, item, "$<CONFIG:")) {
            const end = std.mem.indexOfScalar(u8, item, '>') orelse continue;
            const name = item["$<CONFIG:".len..end];
            if (std.ascii.eqlIgnoreCase(name, config_name)) {
                const rest = item[end + 1 ..];
                if (rest.len > 0) out.append(b.allocator, rest) catch unreachable;
            }
        } else {
            out.append(b.allocator, item) catch unreachable;
        }
    }
    return out.toOwnedSlice(b.allocator) catch unreachable;
}

fn concatSlices(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8) ![]const []const u8 {
    var out = try allocator.alloc([]const u8, a.len + b.len);
    @memcpy(out[0..a.len], a);
    @memcpy(out[a.len..], b);
    return out;
}

fn resolveUsageInner(
    allocator: std.mem.Allocator,
    target: CppTarget,
    graph: []const CppTarget,
    visiting: *std.StringHashMap(void),
) !ResolvedUsage {
    if (visiting.contains(target.name)) return error.DependencyCycleDetected;
    try visiting.put(target.name, {});
    defer _ = visiting.remove(target.name);

    var local = target.include_dirs;
    var exported = UsageRequirements{
        .include_dirs = target.include_dirs.include_dirs,
        .compile_definitions = target.include_dirs.compile_definitions,
        .compile_options = target.include_dirs.compile_options,
        .link_libraries = target.include_dirs.link_libraries,
        .link_options = target.include_dirs.link_options,
    };
    var link_libraries: []const []const u8 = &.{};

    for (target.dependencies) |dep| {
        const child = findTarget(graph, dep.name) orelse return error.UnknownTargetDependency;
        const resolved = try resolveUsageInner(allocator, child, graph, visiting);

        switch (dep.visibility) {
            .private => {
                local = try local.merge(allocator, resolved.exported);
                link_libraries = try concatSlices(allocator, link_libraries, &.{dep.name});
            },
            .public => {
                local = try local.merge(allocator, resolved.exported);
                exported = try exported.merge(allocator, resolved.exported);
                link_libraries = try concatSlices(allocator, link_libraries, &.{dep.name});
            },
            .interface => {
                exported = try exported.merge(allocator, resolved.exported);
            },
        }
    }

    return .{
        .local = local,
        .exported = exported,
        .link_libraries = link_libraries,
    };
}

fn findTarget(graph: []const CppTarget, name: []const u8) ?CppTarget {
    for (graph) |target| {
        if (std.mem.eql(u8, target.name, name)) return target;
    }
    return null;
}

fn emitCompileCommands(
    b: *std.Build,
    self: CppExample,
    config: BuildConfig,
    config_name: []const u8,
    public_include_dirs: []const []const u8,
    private_include_dirs: []const []const u8,
    include_dirs: []const []const u8,
    public_defines: []const []const u8,
    private_defines: []const []const u8,
) !void {
    var entries: std.ArrayListUnmanaged(u8) = .empty;
    defer entries.deinit(b.allocator);
    const all_sources = try self.allSourceFiles(b.allocator);

    try entries.appendSlice(b.allocator, "[\n");
    for (all_sources, 0..) |src, idx| {
        const cmd = try buildCompileCommand(
            b,
            self,
            config,
            config_name,
            src,
            public_include_dirs,
            private_include_dirs,
            include_dirs,
            public_defines,
            private_defines,
        );
        defer b.allocator.free(cmd);

        const root_path = b.build_root.path orelse ".";
        const abs_src = b.pathJoin(&.{ root_path, src });
        const abs_dir = root_path;
        const obj = b.pathJoin(&.{ "zig-out", "obj", self.name, b.fmt("{d}.o", .{idx}) });

        const escaped_dir = jsonEscape(b, abs_dir);
        const escaped_file = jsonEscape(b, abs_src);
        const escaped_cmd = jsonEscape(b, cmd);
        const escaped_out = jsonEscape(b, obj);
        defer b.allocator.free(escaped_dir);
        defer b.allocator.free(escaped_file);
        defer b.allocator.free(escaped_cmd);
        defer b.allocator.free(escaped_out);

        try listPrint(
            &entries,
            b.allocator,
            "  {{\"directory\":\"{s}\",\"file\":\"{s}\",\"command\":\"{s}\",\"output\":\"{s}\"}}{s}\n",
            .{ escaped_dir, escaped_file, escaped_cmd, escaped_out, if (idx + 1 == all_sources.len) "" else "," },
        );
    }
    try entries.appendSlice(b.allocator, "]\n");

    const write_files = b.addWriteFiles();
    const cc_path = "compile_commands.json";
    const cc_file = write_files.add(cc_path, entries.items);
    _ = b.addInstallFileWithDir(cc_file, .prefix, cc_path);

    const manifest = try buildToolingManifest(
        b.allocator,
        self,
        config,
        config_name,
        cc_path,
        public_include_dirs,
        private_include_dirs,
        include_dirs,
        public_defines,
        private_defines,
    );
    defer b.allocator.free(manifest);
    const manifest_rel = b.fmt("share/zaza/{s}-{s}-tooling.json", .{ self.name, config_name });
    const manifest_file = write_files.add(manifest_rel, manifest);
    _ = b.addInstallFileWithDir(manifest_file, .prefix, manifest_rel);
}

fn buildCompileCommand(
    b: *std.Build,
    self: CppExample,
    config: BuildConfig,
    config_name: []const u8,
    src: []const u8,
    public_include_dirs: []const []const u8,
    private_include_dirs: []const []const u8,
    include_dirs: []const []const u8,
    public_defines: []const []const u8,
    private_defines: []const []const u8,
) ![]u8 {
    var cmd: std.ArrayListUnmanaged(u8) = .empty;
    // A C target drives through `zig cc`; a C++ target through `zig c++`.
    try cmd.appendSlice(b.allocator, if (self.c_std != null) "zig cc " else "zig c++ ");

    const flags = filterByConfig(b, self.cpp_flags, config_name);
    for (flags) |flag| {
        try listPrint(&cmd, b.allocator, "{s} ", .{flag});
    }
    for (config.cpp_flags) |flag| {
        try listPrint(&cmd, b.allocator, "{s} ", .{flag});
    }
    if (self.c_std) |c_std| {
        try listPrint(&cmd, b.allocator, "-std=c{s} ", .{c_std});
    } else {
        const std_flag = try CppConfig.getStdFlag(b.allocator, self.cpp_std orelse CppConfig.std_version);
        defer b.allocator.free(std_flag);
        try listPrint(&cmd, b.allocator, "{s} -fexceptions -frtti -D_HAS_EXCEPTIONS=1 ", .{std_flag});
    }

    for (public_defines) |def| {
        const flag = ensureDefineFlag(b, def);
        try listPrint(&cmd, b.allocator, "{s} ", .{flag});
    }
    for (private_defines) |def| {
        const flag = ensureDefineFlag(b, def);
        try listPrint(&cmd, b.allocator, "{s} ", .{flag});
    }
    for (config.defines) |def| {
        const flag = ensureDefineFlag(b, def);
        try listPrint(&cmd, b.allocator, "{s} ", .{flag});
    }

    for (public_include_dirs) |dir| {
        try listPrint(&cmd, b.allocator, "-I{s} ", .{dir});
    }
    for (include_dirs) |dir| {
        try listPrint(&cmd, b.allocator, "-I{s} ", .{dir});
    }
    for (private_include_dirs) |dir| {
        try listPrint(&cmd, b.allocator, "-I{s} ", .{dir});
    }
    for (config.system_includes) |dir| {
        try listPrint(&cmd, b.allocator, "-isystem {s} ", .{dir});
    }

    const obj = b.pathJoin(&.{ "zig-out", "obj", self.name, b.fmt("{s}.o", .{std.fs.path.stem(src)}) });
    try listPrint(&cmd, b.allocator, "-c {s} -o {s}", .{ src, obj });
    return cmd.toOwnedSlice(b.allocator);
}

fn emitInstallAndExport(b: *std.Build, self: CppExample, config_name: []const u8) !void {
    _ = config_name;
    const export_name = self.export_name orelse self.name;

    for (self.install_headers) |hdr| {
        const base = std.fs.path.basename(hdr);
        const dest = b.pathJoin(&.{ export_name, base });
        const install_header = b.addInstallHeaderFile(b.path(hdr), dest);
        b.getInstallStep().dependOn(&install_header.step);
    }
    for (self.install_libs) |lib| {
        const base = std.fs.path.basename(lib);
        const install_lib = b.addInstallLibFile(b.path(lib), base);
        b.getInstallStep().dependOn(&install_lib.step);
    }

    if (self.export_cmake) {
        var content: std.ArrayListUnmanaged(u8) = .empty;
        defer content.deinit(b.allocator);

        try content.appendSlice(b.allocator, "get_filename_component(_ZAZA_PREFIX \"${CMAKE_CURRENT_LIST_DIR}/../..\" ABSOLUTE)\n");
        try listPrint(&content, b.allocator, "set(ZAZA_INCLUDE_DIR \"${{_ZAZA_PREFIX}}/include/{s}\")\n", .{export_name});
        try content.appendSlice(b.allocator, "set(ZAZA_LIB_DIR \"${_ZAZA_PREFIX}/lib\")\n");
        if (self.public_link_libs.len > 0 or self.private_link_libs.len > 0) {
            try content.appendSlice(b.allocator, "set(ZAZA_LIBRARIES ");
            for (self.public_link_libs) |lib| {
                try listPrint(&content, b.allocator, "{s} ", .{lib});
            }
            for (self.private_link_libs) |lib| {
                try listPrint(&content, b.allocator, "{s} ", .{lib});
            }
            try content.appendSlice(b.allocator, ")\n");
        }

        const write_files = b.addWriteFiles();
        const cmake_rel = b.fmt("cmake/{s}/{s}Config.cmake", .{ export_name, export_name });
        const cmake_file = write_files.add(cmake_rel, content.items);
        const install_cmake = b.addInstallFileWithDir(cmake_file, .prefix, cmake_rel);
        b.getInstallStep().dependOn(&install_cmake.step);
    }

    const manifest = try buildPackageManifest(b.allocator, self);
    defer b.allocator.free(manifest);
    const write_files = b.addWriteFiles();
    const manifest_rel = b.fmt("share/zaza/{s}.json", .{export_name});
    const manifest_file = write_files.add(manifest_rel, manifest);
    const install_manifest = b.addInstallFileWithDir(manifest_file, .prefix, manifest_rel);
    b.getInstallStep().dependOn(&install_manifest.step);
}

pub fn buildPackageManifest(allocator: std.mem.Allocator, self: CppExample) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    const export_name = self.export_name orelse self.name;

    try out.appendSlice(allocator, "{\n");
    try listPrint(&out, allocator, "  \"name\": \"{s}\",\n", .{export_name});
    try listPrint(&out, allocator, "  \"kind\": \"{s}\",\n", .{@tagName(self.kind)});
    try writeInstalledIncludeDirs(allocator, &out, export_name, self.install_headers.len > 0);
    try out.appendSlice(allocator, ",\n");
    try writeInstalledHeaders(allocator, &out, export_name, self.install_headers);
    try out.appendSlice(allocator, ",\n");
    try writeInstalledLibs(allocator, &out, self);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "link_libraries", self.public_link_libs);
    try out.appendSlice(allocator, "\n}\n");
    return out.toOwnedSlice(allocator);
}

fn writeInstalledIncludeDirs(gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), export_name: []const u8, has_headers: bool) !void {
    if (!has_headers) {
        try out.appendSlice(gpa, "  \"include_dirs\": []");
        return;
    }
    try listPrint(out, gpa, "  \"include_dirs\": [\"include/{s}\"]", .{export_name});
}

fn writeInstalledHeaders(gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), export_name: []const u8, headers: []const []const u8) !void {
    try out.appendSlice(gpa, "  \"headers\": [");
    for (headers, 0..) |hdr, idx| {
        if (idx > 0) try out.appendSlice(gpa, ", ");
        try listPrint(out, gpa, "\"include/{s}/{s}\"", .{ export_name, std.fs.path.basename(hdr) });
    }
    try out.appendSlice(gpa, "]");
}

fn writeInstalledLibs(allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), self: CppExample) !void {
    try out.appendSlice(allocator, "  \"libs\": [");
    var needs_comma = false;

    switch (self.kind) {
        .static_library, .shared_library => {
            for (self.configs) |config| {
                const rel = try installedArtifactRelativePath(allocator, self, config);
                defer allocator.free(rel);
                if (needs_comma) try out.appendSlice(allocator, ", ");
                try listPrint(out, allocator, "\"{s}\"", .{rel});
                needs_comma = true;
            }
        },
        else => {},
    }

    for (self.install_libs) |lib| {
        if (needs_comma) try out.appendSlice(allocator, ", ");
        try listPrint(out, allocator, "\"lib/{s}\"", .{std.fs.path.basename(lib)});
        needs_comma = true;
    }

    try out.appendSlice(allocator, "]");
}

fn installedArtifactRelativePath(allocator: std.mem.Allocator, self: CppExample, config: BuildConfig) ![]u8 {
    const artifact_name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{
        self.name,
        config.mode.toCMakeString(),
    });
    defer allocator.free(artifact_name);

    const filename = switch (self.kind) {
        .static_library => switch (builtin.os.tag) {
            .windows => try std.fmt.allocPrint(allocator, "{s}.lib", .{artifact_name}),
            else => try std.fmt.allocPrint(allocator, "lib{s}.a", .{artifact_name}),
        },
        .shared_library => switch (builtin.os.tag) {
            .windows => try std.fmt.allocPrint(allocator, "{s}.dll", .{artifact_name}),
            .macos => try std.fmt.allocPrint(allocator, "lib{s}.dylib", .{artifact_name}),
            else => try std.fmt.allocPrint(allocator, "lib{s}.so", .{artifact_name}),
        },
        else => return std.fmt.allocPrint(allocator, "", .{}),
    };
    defer allocator.free(filename);

    return std.fmt.allocPrint(allocator, "lib/{s}", .{filename});
}

pub fn buildToolingManifest(
    allocator: std.mem.Allocator,
    self: CppExample,
    config: BuildConfig,
    config_name: []const u8,
    compile_commands_path: []const u8,
    public_include_dirs: []const []const u8,
    private_include_dirs: []const []const u8,
    include_dirs: []const []const u8,
    public_defines: []const []const u8,
    private_defines: []const []const u8,
) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "{\n");
    try listPrint(&out, allocator, "  \"name\": \"{s}\",\n", .{self.name});
    try listPrint(&out, allocator, "  \"config\": \"{s}\",\n", .{config_name});
    try listPrint(&out, allocator, "  \"compile_commands\": \"{s}\",\n", .{compile_commands_path});
    try writeJsonStringArray(allocator, &out, "include_dirs", public_include_dirs);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "private_include_dirs", private_include_dirs);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "internal_include_dirs", include_dirs);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "system_includes", config.system_includes);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "public_defines", public_defines);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "private_defines", private_defines);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "link_paths", config.link_paths);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "link_files", config.link_files);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "link_frameworks", config.link_frameworks);
    try out.appendSlice(allocator, ",\n");
    try writeJsonStringArray(allocator, &out, "link_libs", config.link_libs);
    try out.appendSlice(allocator, "\n}\n");
    return out.toOwnedSlice(allocator);
}

fn writeJsonStringArray(gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8), key: []const u8, values: []const []const u8) !void {
    try listPrint(out, gpa, "  \"{s}\": [", .{key});
    for (values, 0..) |value, idx| {
        if (idx > 0) try out.appendSlice(gpa, ", ");
        try listPrint(out, gpa, "\"{s}\"", .{value});
    }
    try out.append(gpa, ']');
}

fn jsonEscape(b: *std.Build, input: []const u8) []u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    for (input) |c| {
        switch (c) {
            '"' => out.appendSlice(b.allocator, "\\\"") catch unreachable,
            '\\' => out.appendSlice(b.allocator, "\\\\") catch unreachable,
            '\n' => out.appendSlice(b.allocator, "\\n") catch unreachable,
            '\r' => out.appendSlice(b.allocator, "\\r") catch unreachable,
            '\t' => out.appendSlice(b.allocator, "\\t") catch unreachable,
            else => out.append(b.allocator, c) catch unreachable,
        }
    }
    return out.toOwnedSlice(b.allocator) catch unreachable;
}

pub const CppConfig = struct {
    pub const std_version = "17"; // Default C++ standard

    const required_flags = [_][]const u8{
        "-fexceptions",
        "-frtti",
        "-fno-sanitize=undefined",
        "-x",
        "c++",
        "-Wno-everything",
    };

    pub fn getStdFlag(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
        var flag: std.ArrayListUnmanaged(u8) = .empty;
        try flag.appendSlice(allocator, "-std=c++");
        try flag.appendSlice(allocator, version);
        return flag.toOwnedSlice(allocator);
    }

    pub fn getCMakeFlags(b: *std.Build, mode: BuildMode, cpp_std: ?[]const u8) ![]const u8 {
        const target = b.standardTargetOptions(.{}).query.zigTriple(b.allocator) catch "native";
        const opt_level = switch (mode) {
            .Debug => "Debug",
            .Release => "ReleaseFast",
            .RelWithDebInfo => "ReleaseSafe",
            .MinSizeRel => "ReleaseSmall",
        };

        var flags: std.ArrayListUnmanaged(u8) = .empty;
        defer flags.deinit(b.allocator);

        try listPrint(&flags, b.allocator, "-target {s} -O{s} ", .{ target, opt_level });

        // Add all flags except the standard version
        for (required_flags) |flag| {
            try listPrint(&flags, b.allocator, "{s} ", .{flag});
        }

        // Add the C++ standard version (custom or default)
        const std_flag = try getStdFlag(b.allocator, cpp_std orelse std_version);
        defer b.allocator.free(std_flag);
        try listPrint(&flags, b.allocator, "{s}", .{std_flag});

        return flags.toOwnedSlice(b.allocator);
    }
};

/// Helper for managing C++ compilation flags
pub const CppFlags = struct {
    flags: std.ArrayListUnmanaged([]const u8),
    cpp_std: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CppFlags {
        return .{
            .flags = .empty,
            .cpp_std = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CppFlags) void {
        self.flags.deinit(self.allocator);
    }

    pub fn setCppStd(self: *CppFlags, version: []const u8) void {
        self.cpp_std = version;
    }

    pub fn add(self: *CppFlags, flag: []const u8) !void {
        // Don't add C++ standard flags through this method
        if (std.mem.startsWith(u8, flag, "-std=")) return;

        // Check if flag already exists
        for (self.flags.items) |existing| {
            if (std.mem.eql(u8, flag, existing)) return;
        }
        try self.flags.append(self.allocator, flag);
    }

    pub fn addSlice(self: *CppFlags, new_flags: []const []const u8) !void {
        for (new_flags) |flag| {
            try self.add(flag);
        }
    }

    pub fn ensureRequiredFlags(self: *CppFlags) !void {
        // Add the C++ standard first
        const std_flag = try CppConfig.getStdFlag(self.allocator, self.cpp_std orelse CppConfig.std_version);
        try self.flags.append(self.allocator, std_flag);

        // Add other required flags
        for (CppConfig.required_flags[1..]) |flag| {
            try self.add(flag);
        }
    }

    pub fn toOwnedSlice(self: *CppFlags) ![]const []const u8 {
        return try self.flags.toOwnedSlice(self.allocator);
    }
};

fn hasCMakeFlag(args: []const []const u8, name: []const u8) bool {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-D")) {
            const rest = arg[2..];
            if (std.mem.startsWith(u8, rest, name)) return true;
        }
    }
    return false;
}

fn ensureDefineFlag(b: *std.Build, def: []const u8) []const u8 {
    if (std.mem.startsWith(u8, def, "-D")) return def;
    return b.fmt("-D{s}", .{def});
}
