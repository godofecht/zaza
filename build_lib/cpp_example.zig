const std = @import("std");
const builtin = @import("builtin");
const vex_cmd = @import("vex_cmd.zig");

pub const Dependency = struct {
    name: []const u8,
    url: []const u8,
    include_path: ?[]const u8 = null,
    type: ?BuildSystem = null,  // null means "use parent's build system"
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
        .type = null,  // Use parent's build system
        .build_command = &.{},
    };
};

/// Common build configurations
pub const BuildConfigs = struct {
    pub const debug_release = &.{
        .{
            .mode = .Debug,
            .defines = &.{"DEBUG=1"},
        },
        .{
            .mode = .Release,
            .defines = &.{"NDEBUG=1"},
        },
    };

    pub const debug_only = &.{
        .{
            .mode = .Debug,
            .defines = &.{"DEBUG=1"},
        },
    };

    pub const release_only = &.{
        .{
            .mode = .Release,
            .defines = &.{"NDEBUG=1"},
        },
    };
};

pub const BuildSystem = enum {
    Zig,
    CMake,
};

pub const TargetKind = enum {
    executable,
    static_library,
    shared_library,
    object_library,
    interface_library,
};

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
            .Debug => &.{"-g", "-O0"},
            .Release => &.{"-O3"},
            .RelWithDebInfo => &.{"-g", "-O2"},
            .MinSizeRel => &.{"-Os"},
        };
    }
};

pub const BuildConfig = struct {
    mode: BuildMode,
    target: ?[]const u8 = null,
    defines: []const []const u8 = &.{},
    system_includes: []const []const u8 = &.{},
    link_paths: []const []const u8 = &.{},
    link_libs: []const []const u8 = &.{},
};

fn makeCloneCommand(b: *std.Build, dep: Dependency) []const []const u8 {
    const url = normalizeGitUrl(b, dep.url);
    var args = std.ArrayList([]const u8).init(b.allocator);
    if (builtin.os.tag == .windows) {
        args.appendSlice(&.{
            "cmd.exe",
            "/c",
            b.fmt(
                "if not exist deps\\{s} git clone --depth 1 {s} deps/{s}",
                .{ dep.name, url, dep.name }
            ),
        }) catch unreachable;
    } else {
        args.appendSlice(&.{
            "sh",
            "-c",
            b.fmt(
                "test -d deps/{s} || git clone --depth 1 {s} deps/{s}",
                .{ dep.name, url, dep.name }
            ),
        }) catch unreachable;
    }
    return args.toOwnedSlice() catch unreachable;
}

fn makeSubmoduleInitCommand(b: *std.Build, dep_name: []const u8) []const []const u8 {
    var args = std.ArrayList([]const u8).init(b.allocator);
    if (builtin.os.tag == .windows) {
        args.appendSlice(&.{
            "cmd.exe",
            "/c",
            b.fmt(
                "cd deps\\{s} && git submodule update --init --recursive",
                .{dep_name}
            ),
        }) catch unreachable;
    } else {
        args.appendSlice(&.{
            "sh",
            "-c",
            b.fmt(
                "cd deps/{s} && git submodule update --init --recursive",
                .{dep_name}
            ),
        }) catch unreachable;
    }
    return args.toOwnedSlice() catch unreachable;
}

fn needsSubmoduleInit(dep_name: []const u8) bool {
    return std.mem.eql(u8, dep_name, "mbedtls");
}

fn normalizeGitUrl(b: *std.Build, url: []const u8) []const u8 {
    const https_prefix = "https://github.com/";
    if (std.mem.startsWith(u8, url, https_prefix)) {
        const rest = url[https_prefix.len..];
        return b.fmt("git@github.com:{s}", .{rest});
    }
    return url;
}

fn buildDefaultCMakeArgs(b: *std.Build, dep_name: []const u8, user_args: []const []const u8) []const []const u8 {
    var args = std.ArrayList([]const u8).init(b.allocator);
    if (std.mem.eql(u8, dep_name, "juce")) {
        args.appendSlice(&.{
            "-DJUCE_BUILD_EXAMPLES=OFF",
            "-DJUCE_BUILD_EXTRAS=OFF",
            "-DJUCE_MODULES_ONLY=ON",
            "-DJUCE_GENERATE_JUCE_HEADER=ON",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "json")) {
        args.appendSlice(&.{
            "-DJSON_BuildTests=OFF",
            "-DJSON_Install=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "fmt")) {
        args.appendSlice(&.{
            "-DFMT_DOC=OFF",
            "-DFMT_TEST=OFF",
            "-DBUILD_SHARED_LIBS=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "spdlog")) {
        args.appendSlice(&.{
            "-DSPDLOG_BUILD_EXAMPLE=OFF",
            "-DSPDLOG_BUILD_TESTS=OFF",
            "-DSPDLOG_BUILD_BENCH=OFF",
            "-DBUILD_SHARED_LIBS=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "curl")) {
        args.appendSlice(&.{
            "-DBUILD_CURL_EXE=OFF",
            "-DBUILD_SHARED_LIBS=OFF",
            "-DBUILD_TESTING=OFF",
            "-DCURL_DISABLE_TESTS=ON",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "zlib")) {
        args.appendSlice(&.{
            "-DBUILD_SHARED_LIBS=OFF",
        }) catch unreachable;
    } else if (std.mem.eql(u8, dep_name, "mbedtls")) {
        args.appendSlice(&.{
            "-DENABLE_PROGRAMS=OFF",
            "-DENABLE_TESTING=OFF",
            "-DMBEDTLS_BUILD_SHARED_LIBS=OFF",
            "-DMBEDTLS_FATAL_WARNINGS=OFF",
            "-DUSE_STATIC_MBEDTLS_LIBRARY=ON",
            "-DUSE_SHARED_MBEDTLS_LIBRARY=OFF",
        }) catch unreachable;
    }
    args.appendSlice(user_args) catch unreachable;
    return args.toOwnedSlice() catch unreachable;
}

fn chooseCMakeGenerator(b: *std.Build) ?[]const u8 {
    const env_gen = std.process.getEnvVarOwned(b.allocator, "CMAKE_GENERATOR") catch null;
    if (env_gen) |gen| return gen;
    return null;
}

fn chooseCMakeToolchain(b: *std.Build) ?[]const u8 {
    const env_toolchain = std.process.getEnvVarOwned(b.allocator, "CMAKE_TOOLCHAIN_FILE") catch null;
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
    var args = std.ArrayList([]const u8).init(b.allocator);
    args.appendSlice(&.{"cmake", "-S", source_dir, "-B", build_dir}) catch unreachable;
    if (generator orelse chooseCMakeGenerator(b)) |gen| {
        args.appendSlice(&.{"-G", gen}) catch unreachable;
    }
    args.append(b.fmt("-DCMAKE_BUILD_TYPE={s}", .{config_name})) catch unreachable;
    if (toolchain_file orelse chooseCMakeToolchain(b)) |toolchain| {
        args.append(b.fmt("-DCMAKE_TOOLCHAIN_FILE={s}", .{toolchain})) catch unreachable;
    }
    if (install_prefix) |prefix| {
        args.append(b.fmt("-DCMAKE_INSTALL_PREFIX={s}", .{prefix})) catch unreachable;
    }
    if (!hasCMakeFlag(extra_args, "CMAKE_EXPORT_COMPILE_COMMANDS")) {
        args.append("-DCMAKE_EXPORT_COMPILE_COMMANDS=ON") catch unreachable;
    }
    args.appendSlice(extra_args) catch unreachable;
    return args.toOwnedSlice() catch unreachable;
}

fn makeCMakeBuildCommand(
    b: *std.Build,
    build_dir: []const u8,
    config_name: []const u8,
    extra_args: []const []const u8,
) []const []const u8 {
    var args = std.ArrayList([]const u8).init(b.allocator);
    args.appendSlice(&.{"cmake", "--build", build_dir, "--config", config_name}) catch unreachable;
    args.appendSlice(extra_args) catch unreachable;
    return args.toOwnedSlice() catch unreachable;
}

fn makeCMakeInstallCommand(
    b: *std.Build,
    build_dir: []const u8,
    config_name: []const u8,
    install_prefix: ?[]const u8,
    extra_args: []const []const u8,
) []const []const u8 {
    var args = std.ArrayList([]const u8).init(b.allocator);
    args.appendSlice(&.{"cmake", "--install", build_dir, "--config", config_name}) catch unreachable;
    if (install_prefix) |prefix| {
        args.appendSlice(&.{"--prefix", prefix}) catch unreachable;
    }
    args.appendSlice(extra_args) catch unreachable;
    return args.toOwnedSlice() catch unreachable;
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
        .defines = &.{"DEBUG=1", "NDEBUG=1"},
    };

    pub const MinSizeRel = BuildConfig{
        .mode = .MinSizeRel,
        .defines = &.{"NDEBUG=1"},
    };
};

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
    export_cmake: bool = false,
    export_name: ?[]const u8 = null,
    deps: []const Dependency,
    configs: []const BuildConfig,
    deps_build_system: BuildSystem,
    main_build_system: BuildSystem,
    cpp_std: ?[]const u8,
    cmake_config: ?CMakeConfig = null,
    enable_system_commands: bool = false,

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
        for (self.deps) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.url);
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
        fn write(writer: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
            try writer.writer().print(fmt ++ "\n", args);
        }

        fn section(writer: *std.ArrayList(u8), name: []const u8, args: []const []const u8) !void {
            try writer.writer().print("{s}(", .{name});
            for (args, 0..) |arg, i| {
                if (i > 0) try writer.appendSlice(" ");
                try writer.appendSlice(arg);
            }
            try writer.appendSlice(")\n");
        }

        fn list(writer: *std.ArrayList(u8), name: []const u8, target: []const u8, items: []const []const u8) !void {
            try listScoped(writer, name, target, "PRIVATE", items);
        }

        fn listScoped(writer: *std.ArrayList(u8), name: []const u8, target: []const u8, scope: []const u8, items: []const []const u8) !void {
            try writer.writer().print("{s}({s} {s}\n", .{name, target, scope});
            for (items) |item| {
                try writer.writer().print("    {s}\n", .{item});
            }
            try writer.appendSlice(")\n\n");
        }
    };

    pub fn getExeName(self: CppExample, b: *std.Build, config: BuildConfig) []const u8 {
        return b.fmt("{s}_{s}", .{ self.name, config.mode.toCMakeString() });
    }

    pub fn targetName(self: CppExample) []const u8 {
        return self.name;
    }

    pub fn generateCMake(self: CppExample, b: *std.Build) !void {
        var writer = std.ArrayList(u8).init(b.allocator);
        defer writer.deinit();

        // Header
        try cmake.write(&writer, "cmake_minimum_required(VERSION 3.15)", .{});
        try cmake.write(&writer, "", .{});
        try cmake.section(&writer, "project", &.{self.name});
        try cmake.write(&writer, "", .{});

        // Add dependencies
        for (self.deps) |dep| {
            try cmake.write(&writer, "add_subdirectory(deps/{s})", .{dep.name});
        }
        try cmake.write(&writer, "", .{});

        // Create target
        switch (self.kind) {
            .executable => try cmake.write(&writer, "add_executable({s}", .{self.name}),
            .static_library => try cmake.write(&writer, "add_library({s} STATIC", .{self.name}),
            .shared_library => try cmake.write(&writer, "add_library({s} SHARED", .{self.name}),
            .object_library => try cmake.write(&writer, "add_library({s} OBJECT", .{self.name}),
            .interface_library => try cmake.write(&writer, "add_library({s} INTERFACE)", .{self.name}),
        }
        if (self.kind != .interface_library) {
            for (self.source_files) |src| {
                try cmake.write(&writer, "    {s}", .{src});
            }
            try cmake.write(&writer, ")", .{});
        }
        try cmake.write(&writer, "", .{});

        // Include directories
        if (self.public_include_dirs.len > 0) {
            try cmake.listScoped(&writer, "target_include_directories", self.name, "PUBLIC", self.public_include_dirs);
        }
        if (self.include_dirs.len > 0 or self.private_include_dirs.len > 0) {
            var all_private = std.ArrayList([]const u8).init(b.allocator);
            defer all_private.deinit();
            try all_private.appendSlice(self.include_dirs);
            try all_private.appendSlice(self.private_include_dirs);
            if (all_private.items.len > 0) {
                try cmake.listScoped(&writer, "target_include_directories", self.name, "PRIVATE", all_private.items);
            }
        }

        // Compiler flags
        var flags = std.ArrayList([]const u8).init(b.allocator);
        defer flags.deinit();

        // Add C++ standard
        const std_flag = try std.fmt.allocPrint(b.allocator, "-std=c++{s}", .{self.cpp_std orelse "17"});
        try flags.append(std_flag);

        // Add other flags
        try flags.appendSlice(self.cpp_flags);

        try cmake.list(&writer, "target_compile_options", self.name, flags.items);

        // Compile definitions
        if (self.public_defines.len > 0) {
            try cmake.listScoped(&writer, "target_compile_definitions", self.name, "PUBLIC", self.public_defines);
        }
        if (self.private_defines.len > 0) {
            try cmake.listScoped(&writer, "target_compile_definitions", self.name, "PRIVATE", self.private_defines);
        }

        // Link libraries
        if (self.public_link_libs.len > 0) {
            try cmake.listScoped(&writer, "target_link_libraries", self.name, "PUBLIC", self.public_link_libs);
        }
        if (self.private_link_libs.len > 0) {
            try cmake.listScoped(&writer, "target_link_libraries", self.name, "PRIVATE", self.private_link_libs);
        }

        // Write CMakeLists.txt
        try b.build_root.handle.writeFile(.{
            .sub_path = "CMakeLists.txt",
            .data = writer.items,
        });
    }

    pub fn build(self: CppExample, b: *std.Build) !*std.Build.Step.Compile {
        const target = b.standardTargetOptions(.{});
        return self.buildWithTarget(b, target);
    }

    pub fn buildWithTarget(self: CppExample, b: *std.Build, target: std.Build.ResolvedTarget) !*std.Build.Step.Compile {
        if (target.result.os.tag == .windows and target.result.abi == .msvc and self.main_build_system == .Zig) {
            @panic(
                "Zig 0.14 cannot compile C++ with the MSVC ABI (see Zig issue #18685). "
                ++ "Use VEX_WINDOWS_TOOLCHAIN=gnu or VEX_TARGET=x86_64-windows-gnu, "
                ++ "or switch this example to a system toolchain (CMake)."
            );
        }
        // Generate CMakeLists.txt first
        try self.generateCMake(b);
        
        // Print build information (disabled in build runner to avoid crashes)

        var last_exe: ?*std.Build.Step.Compile = null;
        var final_steps = std.ArrayList(*std.Build.Step).init(b.allocator);
        defer final_steps.deinit();

        // For each configuration
        for (self.configs) |config| {
            const config_name = config.mode.toCMakeString();
            
            var last_step: ?*std.Build.Step = null;

            // Clone and build dependencies (optional)
            if (self.enable_system_commands) {
                for (self.deps) |dep| {
                    // Clone step
                    const clone_step = vex_cmd.addCommandStep(
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
                        const submodule_step = vex_cmd.addCommandStep(
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
                        const dep_source_dir = cmake_cfg.source_dir orelse b.pathJoin(&.{"deps", dep.name});
                        const dep_build_dir = cmake_cfg.build_dir orelse b.pathJoin(&.{"deps", dep.name, "build", config_name});
                        const extra_configure_args = buildDefaultCMakeArgs(b, dep.name, cmake_cfg.configure_args);

                        const configure_step = vex_cmd.addCommandStep(
                            b,
                            b.fmt("configure_{s}_{s}", .{ dep.name, config_name }),
                            makeCMakeConfigureCommand(
                                b,
                                dep_source_dir,
                                dep_build_dir,
                                config_name,
                                cmake_cfg.generator,
                                cmake_cfg.toolchain_file,
                                cmake_cfg.install_prefix,
                                extra_configure_args,
                            )
                        );
                        if (last_step) |prev| {
                            configure_step.dependencies.append(prev) catch unreachable;
                        }
                        last_step = configure_step;

                        const build_step = vex_cmd.addCommandStep(
                            b,
                            b.fmt("build_{s}_{s}", .{ dep.name, config_name }),
                            makeCMakeBuildCommand(
                                b,
                                dep_build_dir,
                                config_name,
                                cmake_cfg.build_args,
                            )
                        );
                        build_step.dependencies.append(configure_step) catch unreachable;
                        last_step = build_step;
                        if (cmake_cfg.install) {
                            const install_step = vex_cmd.addCommandStep(
                                b,
                                b.fmt("install_{s}_{s}", .{ dep.name, config_name }),
                                makeCMakeInstallCommand(
                                    b,
                                    dep_build_dir,
                                    config_name,
                                    cmake_cfg.install_prefix,
                                    cmake_cfg.install_args,
                                )
                            );
                            install_step.dependencies.append(build_step) catch unreachable;
                            last_step = install_step;
                        }
                    } else if (dep.build_command.len > 0) {
                        const cmd_step = vex_cmd.addCommandStep(
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

            // Build main project with selected build system
            if (self.main_build_system == .CMake) {
                if (!self.enable_system_commands) return error.SystemCommandsDisabled;
                // Use CMake for main project
                const cmake_cfg = self.cmake_config orelse CMakeConfig{};
                const source_dir = cmake_cfg.source_dir orelse ".";
                const build_dir = cmake_cfg.build_dir orelse b.pathJoin(&.{"build", config_name});
                const cmake_configure = vex_cmd.addCommandStep(
                    b,
                    b.fmt("configure_{s}_{s}", .{ self.name, config_name }),
                    makeCMakeConfigureCommand(
                        b,
                        source_dir,
                        build_dir,
                        config_name,
                        cmake_cfg.generator,
                        cmake_cfg.toolchain_file,
                        cmake_cfg.install_prefix,
                        cmake_cfg.configure_args,
                    )
                );
                if (last_step) |prev| cmake_configure.dependencies.append(prev) catch unreachable;

                const cmake_build = vex_cmd.addCommandStep(
                    b,
                    b.fmt("build_{s}_{s}", .{ self.name, config_name }),
                    makeCMakeBuildCommand(
                        b,
                        build_dir,
                        config_name,
                        cmake_cfg.build_args,
                    )
                );
                cmake_build.dependencies.append(cmake_configure) catch unreachable;
                last_step = cmake_build;
                if (cmake_cfg.install) {
                    const cmake_install = vex_cmd.addCommandStep(
                        b,
                        b.fmt("install_{s}_{s}", .{ self.name, config_name }),
                        makeCMakeInstallCommand(
                            b,
                            build_dir,
                            config_name,
                            cmake_cfg.install_prefix,
                            cmake_cfg.install_args,
                        )
                    );
                    cmake_install.dependencies.append(cmake_build) catch unreachable;
                    last_step = cmake_install;
                }
                if (last_step) |step| {
                    final_steps.append(step) catch unreachable;
                }
                try emitInstallAndExport(b, self, config_name);
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

                // Add source files with C++ flags
                var cpp_flags_list = std.ArrayList([]const u8).init(b.allocator);
                defer cpp_flags_list.deinit();

                // Add user flags
                try cpp_flags_list.appendSlice(filterByConfig(b, self.cpp_flags, config_name));
                
                // Add required flags
                try cpp_flags_list.append(try CppConfig.getStdFlag(b.allocator, self.cpp_std orelse CppConfig.std_version));
                try cpp_flags_list.appendSlice(&.{
                    "-fexceptions",
                    "-frtti",
                    "-D_HAS_EXCEPTIONS=1",
                });
                // Add compile definitions (public/private treated the same in Zig build)
                for (public_defines) |def| {
                    try cpp_flags_list.append(ensureDefineFlag(b, def));
                }
                for (private_defines) |def| {
                    try cpp_flags_list.append(ensureDefineFlag(b, def));
                }
                for (config.defines) |def| {
                    try cpp_flags_list.append(ensureDefineFlag(b, def));
                }

                if (self.kind != .interface_library) {
                    compile.addCSourceFiles(.{
                        .files = self.source_files,
                        .flags = try cpp_flags_list.toOwnedSlice(),
                    });
                }

                // Add include directories
                for (public_include_dirs) |dir| {
                    compile.addIncludePath(.{ .cwd_relative = dir });
                }
                for (include_dirs) |dir| {
                    compile.addIncludePath(.{ .cwd_relative = dir });
                }
                for (private_include_dirs) |dir| {
                    compile.addIncludePath(.{ .cwd_relative = dir });
                }
                // Add system include directories from build config
                for (config.system_includes) |dir| {
                    compile.addSystemIncludePath(.{ .cwd_relative = dir });
                }
                // Add include directories from Zig package deps
                for (self.deps) |dep| {
                    if (dep.pkg_name) |pkg_name| {
                        const pkg = b.dependency(pkg_name, .{});
                        const include_subdir = dep.pkg_include orelse ".";
                        compile.addIncludePath(pkg.path(include_subdir));
                    }
                }

                // Link C++ runtime
                if (self.kind != .object_library and self.kind != .interface_library) {
                    compile.linkLibCpp();
                }

                // Link extra libraries from build config
                for (config.link_paths) |lib_path| {
                    compile.addLibraryPath(.{ .cwd_relative = lib_path });
                }
                for (config.link_libs) |lib| {
                    compile.linkSystemLibrary(lib);
                }
                for (public_link_libs) |lib| {
                    compile.linkSystemLibrary(lib);
                }
                for (private_link_libs) |lib| {
                    compile.linkSystemLibrary(lib);
                }

                // Optional: compile_commands.json for Zig builds
                try emitCompileCommands(b, self, config, config_name, public_include_dirs, private_include_dirs, include_dirs, public_defines, private_defines);

                // Optional install + export
                try emitInstallAndExport(b, self, config_name);

                if (last_step) |prev| {
                    compile.step.dependencies.append(prev) catch unreachable;
                }
                last_step = &compile.step;
                last_exe = compile;
            }

            if (last_step) |step| {
                final_steps.append(step) catch unreachable;
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
        /// JUCE git tag/branch (e.g. "7.0.9", "7.0.12", "master")
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
        fn write(writer: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
            try writer.writer().print(fmt ++ "\n", args);
        }

        fn section(writer: *std.ArrayList(u8), name: []const u8, args: []const []const u8) !void {
            try writer.writer().print("{s}(", .{name});
            for (args, 0..) |arg, i| {
                if (i > 0) try writer.appendSlice(" ");
                try writer.appendSlice(arg);
            }
            try writer.appendSlice(")\n");
        }

        fn list(writer: *std.ArrayList(u8), name: []const u8, target: []const u8, items: []const []const u8) !void {
            try writer.writer().print("{s}({s} PRIVATE\n", .{name, target});
            for (items) |item| {
                try writer.writer().print("    {s}\n", .{item});
            }
            try writer.appendSlice(")\n\n");
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
        sources: std.ArrayList([]const u8),
        modules: std.ArrayList([]const u8),
        build_mode: BuildMode = .Debug,
        cpp_std: ?[]const u8 = null,
        cmake_root: []const u8 = ".",
        juce_git_tag: ?[]const u8 = null,

        pub fn init(b: *std.Build) Builder {
            return .{
                .b = b,
                .sources = std.ArrayList([]const u8).init(b.allocator),
                .modules = std.ArrayList([]const u8).init(b.allocator),
            };
        }

        pub fn deinit(self: *Builder) void {
            self.sources.deinit();
            self.modules.deinit();
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
                try self.sources.append(src);
            }
            for (config.modules) |module| {
                try self.modules.append(module);
            }
            return self;
        }

        pub fn addSource(self: *Builder, source: []const u8) !*Builder {
            try self.sources.append(source);
            return self;
        }

        pub fn addModule(self: *Builder, module: []const u8) !*Builder {
            try self.modules.append(module);
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
            const writer = try self.b.allocator.create(std.ArrayList(u8));
            writer.* = std.ArrayList(u8).init(self.b.allocator);
            defer writer.deinit();

            // Header
            try cmake.write(writer, "cmake_minimum_required(VERSION 3.15)", .{});
            try cmake.write(writer, "", .{});
            try cmake.section(writer, "project", &.{self.name, "VERSION", self.version});
            try cmake.write(writer, "include(FetchContent)", .{});
            try cmake.write(writer, "set(FETCHCONTENT_QUIET OFF)", .{});
            try cmake.write(writer, "set(FETCHCONTENT_UPDATES_DISCONNECTED ON)", .{});
            try cmake.write(writer, "if (DEFINED JUCE_SOURCE_DIR)", .{});
            try cmake.write(writer, "    set(FETCHCONTENT_SOURCE_DIR_JUCE \"${{JUCE_SOURCE_DIR}}\")", .{});
            try cmake.write(writer, "elseif (EXISTS \"${{CMAKE_CURRENT_LIST_DIR}}/deps/juce/CMakeLists.txt\")", .{});
            try cmake.write(writer, "    set(FETCHCONTENT_SOURCE_DIR_JUCE \"${{CMAKE_CURRENT_LIST_DIR}}/deps/juce\")", .{});
            try cmake.write(writer, "endif()", .{});
            if (self.juce_git_tag) |tag| {
                try cmake.write(writer, "set(JUCE_GIT_TAG \"{s}\")", .{tag});
            } else {
                try cmake.write(writer, "if (NOT DEFINED JUCE_GIT_TAG)", .{});
                try cmake.write(writer, "    set(JUCE_GIT_TAG \"master\")", .{});
                try cmake.write(writer, "endif()", .{});
            }
            try cmake.write(writer, "FetchContent_Declare(juce", .{});
            try cmake.write(writer, "    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git", .{});
            try cmake.write(writer, "    GIT_TAG ${{JUCE_GIT_TAG}}", .{});
            try cmake.write(writer, ")", .{});
            try cmake.write(writer, "FetchContent_MakeAvailable(juce)", .{});
            try cmake.write(writer, "", .{});

            // App definition
            try cmake.write(writer, "juce_add_gui_app({s}", .{self.name});
            try cmake.write(writer, "    PRODUCT_NAME \"{s}\"", .{self.name});
            try cmake.write(writer, "    COMPANY_NAME \"{s}\"", .{self.company});
            try cmake.write(writer, "    VERSION \"{s}\"", .{self.version});
            try cmake.write(writer, ")", .{});
            try cmake.write(writer, "", .{});

            // Sources and modules
            try cmake.list(writer, "target_sources", self.name, self.sources.items);
            
            var juce_modules = std.ArrayList([]const u8).init(self.b.allocator);
            defer juce_modules.deinit();
            for (self.modules.items) |module| {
                try juce_modules.append(try std.fmt.allocPrint(self.b.allocator, "juce::{s}", .{module}));
            }
            try cmake.list(writer, "target_link_libraries", self.name, juce_modules.items);

            // C++ standard
            try cmake.section(writer, "target_compile_features", &.{self.name, "PRIVATE", "cxx_std_17"});

            // Write CMakeLists.txt
            const cmake_path = if (std.mem.eql(u8, self.cmake_root, "."))
                "CMakeLists.txt"
            else
                self.b.pathJoin(&.{ self.cmake_root, "CMakeLists.txt" });
            try self.b.build_root.handle.writeFile(.{
                .sub_path = cmake_path,
                .data = writer.items,
            });

            // Create CppExample
            const example = try self.b.allocator.create(CppExample);
            example.* = .{
                .name = self.name,
                .description = self.description,
                .source_files = try self.sources.toOwnedSlice(),
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

    return switch (self.kind) {
        .executable => b.addExecutable(.{
            .name = self.getExeName(b, config),
            .target = target,
            .optimize = optimize,
            .root_source_file = null,
        }),
        .static_library => b.addStaticLibrary(.{
            .name = self.getExeName(b, config),
            .target = target,
            .optimize = optimize,
            .root_source_file = null,
        }),
        .shared_library => b.addSharedLibrary(.{
            .name = self.getExeName(b, config),
            .target = target,
            .optimize = optimize,
            .root_source_file = null,
        }),
        .object_library => b.addObject(.{
            .name = self.getExeName(b, config),
            .target = target,
            .optimize = optimize,
            .root_source_file = null,
        }),
        .interface_library => b.addStaticLibrary(.{
            .name = self.getExeName(b, config),
            .target = target,
            .optimize = optimize,
            .root_source_file = null,
        }),
    };
}

fn filterByConfig(b: *std.Build, items: []const []const u8, config_name: []const u8) []const []const u8 {
    var out = std.ArrayList([]const u8).init(b.allocator);
    for (items) |item| {
        if (std.mem.startsWith(u8, item, "$<CONFIG:")) {
            const end = std.mem.indexOfScalar(u8, item, '>') orelse continue;
            const name = item["$<CONFIG:".len..end];
            if (std.ascii.eqlIgnoreCase(name, config_name)) {
                const rest = item[end + 1 ..];
                if (rest.len > 0) out.append(rest) catch unreachable;
            }
        } else {
            out.append(item) catch unreachable;
        }
    }
    return out.toOwnedSlice() catch unreachable;
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
    var entries = std.ArrayList(u8).init(b.allocator);
    defer entries.deinit();

    try entries.appendSlice("[\n");
    for (self.source_files, 0..) |src, idx| {
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

        try entries.writer().print(
            "  {{\"directory\":\"{s}\",\"file\":\"{s}\",\"command\":\"{s}\",\"output\":\"{s}\"}}{s}\n",
            .{ escaped_dir, escaped_file, escaped_cmd, escaped_out, if (idx + 1 == self.source_files.len) "" else "," },
        );
    }
    try entries.appendSlice("]\n");

    const write_files = b.addWriteFiles();
    const cc_path = "compile_commands.json";
    const cc_file = write_files.add(cc_path, entries.items);
    _ = b.addInstallFileWithDir(cc_file, .prefix, cc_path);
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
    var cmd = std.ArrayList(u8).init(b.allocator);
    try cmd.appendSlice("zig c++ ");

    const flags = filterByConfig(b, self.cpp_flags, config_name);
    for (flags) |flag| {
        try cmd.writer().print("{s} ", .{flag});
    }
    const std_flag = try CppConfig.getStdFlag(b.allocator, self.cpp_std orelse CppConfig.std_version);
    defer b.allocator.free(std_flag);
    try cmd.writer().print("{s} -fexceptions -frtti -D_HAS_EXCEPTIONS=1 ", .{std_flag});

    for (public_defines) |def| {
        const flag = ensureDefineFlag(b, def);
        try cmd.writer().print("{s} ", .{flag});
    }
    for (private_defines) |def| {
        const flag = ensureDefineFlag(b, def);
        try cmd.writer().print("{s} ", .{flag});
    }
    for (config.defines) |def| {
        const flag = ensureDefineFlag(b, def);
        try cmd.writer().print("{s} ", .{flag});
    }

    for (public_include_dirs) |dir| {
        try cmd.writer().print("-I{s} ", .{dir});
    }
    for (include_dirs) |dir| {
        try cmd.writer().print("-I{s} ", .{dir});
    }
    for (private_include_dirs) |dir| {
        try cmd.writer().print("-I{s} ", .{dir});
    }
    for (config.system_includes) |dir| {
        try cmd.writer().print("-isystem {s} ", .{dir});
    }

    const obj = b.pathJoin(&.{ "zig-out", "obj", self.name, b.fmt("{s}.o", .{std.fs.path.stem(src)}) });
    try cmd.writer().print("-c {s} -o {s}", .{src, obj});
    return cmd.toOwnedSlice();
}

fn emitInstallAndExport(b: *std.Build, self: CppExample, config_name: []const u8) !void {
    _ = config_name;
    const export_name = self.export_name orelse self.name;

    for (self.install_headers) |hdr| {
        const base = std.fs.path.basename(hdr);
        const dest = b.pathJoin(&.{ export_name, base });
        _ = b.addInstallHeaderFile(b.path(hdr), dest);
    }
    for (self.install_libs) |lib| {
        const base = std.fs.path.basename(lib);
        _ = b.addInstallLibFile(b.path(lib), base);
    }

    if (self.export_cmake) {
        var content = std.ArrayList(u8).init(b.allocator);
        defer content.deinit();

        try content.appendSlice("get_filename_component(_VEX_PREFIX \"${CMAKE_CURRENT_LIST_DIR}/../..\" ABSOLUTE)\n");
        try content.writer().print("set(VEX_INCLUDE_DIR \"${{_VEX_PREFIX}}/include/{s}\")\n", .{export_name});
        try content.appendSlice("set(VEX_LIB_DIR \"${_VEX_PREFIX}/lib\")\n");
        if (self.public_link_libs.len > 0 or self.private_link_libs.len > 0) {
            try content.appendSlice("set(VEX_LIBRARIES ");
            for (self.public_link_libs) |lib| {
                try content.writer().print("{s} ", .{lib});
            }
            for (self.private_link_libs) |lib| {
                try content.writer().print("{s} ", .{lib});
            }
            try content.appendSlice(")\n");
        }

        const write_files = b.addWriteFiles();
        const cmake_rel = b.fmt("cmake/{s}/{s}Config.cmake", .{ export_name, export_name });
        const cmake_file = write_files.add(cmake_rel, content.items);
        _ = b.addInstallFileWithDir(cmake_file, .prefix, cmake_rel);
    }
}

fn jsonEscape(b: *std.Build, input: []const u8) []u8 {
    var out = std.ArrayList(u8).init(b.allocator);
    for (input) |c| {
        switch (c) {
            '"' => out.appendSlice("\\\"") catch unreachable,
            '\\' => out.appendSlice("\\\\") catch unreachable,
            '\n' => out.appendSlice("\\n") catch unreachable,
            '\r' => out.appendSlice("\\r") catch unreachable,
            '\t' => out.appendSlice("\\t") catch unreachable,
            else => out.append(c) catch unreachable,
        }
    }
    return out.toOwnedSlice() catch unreachable;
}

pub const CppConfig = struct {
    pub const std_version = "17";  // Default C++ standard

    const required_flags = [_][]const u8{
        "-fexceptions",
        "-frtti",
        "-fno-sanitize=undefined",
        "-x", "c++",
        "-Wno-everything",
    };

    pub fn getStdFlag(allocator: std.mem.Allocator, version: []const u8) ![]const u8 {
        var flag = std.ArrayList(u8).init(allocator);
        try flag.appendSlice("-std=c++");
        try flag.appendSlice(version);
        return flag.toOwnedSlice();
    }

    pub fn getCMakeFlags(b: *std.Build, mode: BuildMode, cpp_std: ?[]const u8) ![]const u8 {
        const target = b.standardTargetOptions(.{}).query.zigTriple(b.allocator) catch "native";
        const opt_level = switch (mode) {
            .Debug => "Debug",
            .Release => "ReleaseFast",
            .RelWithDebInfo => "ReleaseSafe",
            .MinSizeRel => "ReleaseSmall",
        };
        
        var flags = std.ArrayList(u8).init(b.allocator);
        defer flags.deinit();

        try flags.writer().print("-target {s} -O{s} ", .{target, opt_level});
        
        // Add all flags except the standard version
        for (required_flags) |flag| {
            try flags.writer().print("{s} ", .{flag});
        }
        
        // Add the C++ standard version (custom or default)
        const std_flag = try getStdFlag(b.allocator, cpp_std orelse std_version);
        defer b.allocator.free(std_flag);
        try flags.writer().print("{s}", .{std_flag});
        
        return flags.toOwnedSlice();
    }
};

/// Helper for managing C++ compilation flags
pub const CppFlags = struct {
    flags: std.ArrayList([]const u8),
    cpp_std: ?[]const u8,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) CppFlags {
        return .{
            .flags = std.ArrayList([]const u8).init(allocator),
            .cpp_std = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CppFlags) void {
        self.flags.deinit();
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
        try self.flags.append(flag);
    }

    pub fn addSlice(self: *CppFlags, new_flags: []const []const u8) !void {
        for (new_flags) |flag| {
            try self.add(flag);
        }
    }

    pub fn ensureRequiredFlags(self: *CppFlags) !void {
        // Add the C++ standard first
        const std_flag = try CppConfig.getStdFlag(self.allocator, self.cpp_std orelse CppConfig.std_version);
        try self.flags.append(std_flag);
        
        // Add other required flags
        for (CppConfig.required_flags[1..]) |flag| {
            try self.add(flag);
        }
    }

    pub fn toOwnedSlice(self: *CppFlags) ![]const []const u8 {
        return try self.flags.toOwnedSlice();
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
