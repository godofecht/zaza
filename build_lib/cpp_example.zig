const std = @import("std");

pub const Dependency = struct {
    name: []const u8,
    url: []const u8,
    include_path: ?[]const u8 = null,
    type: ?BuildSystem = null,  // null means "use parent's build system"
    build_command: []const []const u8 = &.{},
    
    pub fn getBuildCommand(self: Dependency, b: *std.Build, config_name: []const u8, parent_build_system: BuildSystem) []const []const u8 {
        const effective_type = self.type orelse parent_build_system;
        if (effective_type == .CMake) {
            // Configure command based on dependency
            var configure_cmd = std.ArrayList([]const u8).init(b.allocator);
            configure_cmd.appendSlice(&.{
                "cmake",
                "-S", b.pathJoin(&.{"deps", self.name}),
                "-B", b.pathJoin(&.{"deps", self.name, "build"}),
                b.fmt("-DCMAKE_BUILD_TYPE={s}", .{config_name}),
            }) catch unreachable;

            // Add dependency-specific flags
            if (std.mem.eql(u8, self.name, "juce")) {
                configure_cmd.appendSlice(&.{
                    "-DJUCE_BUILD_EXAMPLES=OFF",
                    "-DJUCE_BUILD_EXTRAS=OFF",
                    "-DJUCE_MODULES_ONLY=ON",
                    "-DJUCE_GENERATE_JUCE_HEADER=ON",
                }) catch unreachable;
            } else if (std.mem.eql(u8, self.name, "json")) {
                configure_cmd.appendSlice(&.{
                    "-DJSON_BuildTests=OFF",
                    "-DJSON_Install=OFF",
                }) catch unreachable;
            }

            // Create the build command
            const build_cmd = &.{
                "cmake",
                "--build", b.pathJoin(&.{"deps", self.name, "build"}),
                "--config", config_name,
            };

            // Combine into a single command with cmd.exe
            var cmd = std.ArrayList([]const u8).init(b.allocator);
            cmd.appendSlice(&.{"cmd.exe", "/c"}) catch unreachable;
            cmd.appendSlice(configure_cmd.items) catch unreachable;
            cmd.appendSlice(&.{"&&"}) catch unreachable;
            cmd.appendSlice(build_cmd) catch unreachable;
            return cmd.toOwnedSlice() catch unreachable;
        }
        
        // For custom build commands or Zig
        return self.build_command;
    }
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
    source_files: []const []const u8,
    include_dirs: []const []const u8,
    cpp_flags: []const []const u8,
    deps: []const Dependency,
    configs: []const BuildConfig,
    deps_build_system: BuildSystem,
    main_build_system: BuildSystem,
    cpp_std: ?[]const u8,

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
            try writer.writer().print("{s}({s} PRIVATE\n", .{name, target});
            for (items) |item| {
                try writer.writer().print("    {s}\n", .{item});
            }
            try writer.appendSlice(")\n\n");
        }
    };

    pub fn getExeName(self: CppExample, b: *std.Build, config: BuildConfig) []const u8 {
        return b.fmt("{s}_{s}", .{ self.name, config.mode.toCMakeString() });
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

        // Create executable
        try cmake.write(&writer, "add_executable({s}", .{self.name});
        for (self.source_files) |src| {
            try cmake.write(&writer, "    {s}", .{src});
        }
        try cmake.write(&writer, ")", .{});
        try cmake.write(&writer, "", .{});

        // Include directories
        try cmake.list(&writer, "target_include_directories", self.name, self.include_dirs);

        // Compiler flags
        var flags = std.ArrayList([]const u8).init(b.allocator);
        defer flags.deinit();

        // Add C++ standard
        const std_flag = try std.fmt.allocPrint(b.allocator, "-std=c++{s}", .{self.cpp_std orelse "17"});
        try flags.append(std_flag);

        // Add other flags
        try flags.appendSlice(self.cpp_flags);

        try cmake.list(&writer, "target_compile_options", self.name, flags.items);

        // Write CMakeLists.txt
        try b.build_root.handle.writeFile(.{
            .sub_path = "CMakeLists.txt",
            .data = writer.items,
        });
    }

    pub fn build(self: CppExample, b: *std.Build) !*std.Build.Step.Compile {
        // Generate CMakeLists.txt first
        try self.generateCMake(b);
        
        // Print build information
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\n\x1b[1;36m=== Building {s} ===\x1b[0m\n", .{self.name});
        try stdout.print("\x1b[1mDescription:\x1b[0m {s}\n", .{self.description});
        
        // Print dependencies
        try stdout.print("\n\x1b[1mDependencies:\x1b[0m\n", .{});
        for (self.deps) |dep| {
            try stdout.print("  - \x1b[1m{s}\x1b[0m\n", .{dep.name});
            try stdout.print("    URL: {s}\n", .{dep.url});
            const build_system = dep.type orelse self.deps_build_system;
            try stdout.print("    Build System: {s}\n", .{@tagName(build_system)});
        }
        try stdout.print("\n", .{});

        var manager = @import("build_steps.zig").BuildManager.init(b);
        defer manager.deinit();

        var last_step: ?*@import("build_graph.zig").Node = null;
        var last_exe: ?*std.Build.Step.Compile = null;

        // For each configuration
        for (self.configs) |config| {
            const config_name = config.mode.toCMakeString();
            
            // Clone and build dependencies
            for (self.deps) |dep| {
                // Clone step
                const clone = try manager.createStep(
                    b.fmt("clone_{s}_{s}", .{dep.name, config_name}), 
                    b.fmt("Cloning {s} ({s})", .{dep.name, config_name})
                );
                const clone_cmd = b.addSystemCommand(&.{
                    "cmd.exe", "/c",
                    b.fmt(
                        "if not exist deps\\{s} git clone --depth 1 {s} deps/{s}",
                        .{ dep.name, dep.url, dep.name }
                    ),
                });
                clone_cmd.stdio = .inherit;
                clone.cmd_step = &clone_cmd.step;
                if (last_step) |prev| {
                    try manager.addDependency(prev, clone);
                }
                last_step = clone;

                // Build step (only after clone completes)
                if (dep.type == .CMake or dep.build_command.len > 0) {
                    const build_cmd = dep.getBuildCommand(b, config_name, self.deps_build_system);
                    if (build_cmd.len > 0) {
                        const build_dep = try manager.createStep(
                            b.fmt("build_{s}_{s}", .{dep.name, config_name}),
                            b.fmt("Building {s} ({s})", .{dep.name, config_name})
                        );
                        const cmd = b.addSystemCommand(build_cmd);
                        cmd.stdio = .inherit;
                        build_dep.cmd_step = &cmd.step;
                        if (last_step) |prev| {
                            try manager.addDependency(prev, build_dep);
                        }
                        last_step = build_dep;
                    }
                }
            }

            // Build main project with selected build system
            const build_exe = try manager.createStep(
                b.fmt("build_{s}_{s}", .{self.name, config_name}),
                b.fmt("Building {s} ({s})", .{self.name, config_name})
            );

            if (self.main_build_system == .CMake) {
                // Use CMake for main project
                const cmake_configure = b.addSystemCommand(&.{
                    "cmake",
                    "-S", ".",
                    "-B", "build",
                    b.fmt("-DCMAKE_BUILD_TYPE={s}", .{config_name}),
                });
                cmake_configure.stdio = .inherit;
                if (build_exe.cmd_step) |step| {
                    step.dependencies.append(&cmake_configure.step) catch unreachable;
                }

                const cmake_build = b.addSystemCommand(&.{
                    "cmake",
                    "--build", "build",
                    "--config", config_name,
                });
                cmake_build.stdio = .inherit;
                cmake_build.step.dependencies.append(&cmake_configure.step) catch unreachable;
                if (build_exe.cmd_step) |step| {
                    step.dependencies.append(&cmake_build.step) catch unreachable;
                }
            } else {
                // Build with Zig directly since json is header-only
                const exe = b.addExecutable(.{
                    .name = self.getExeName(b, config),
                    .target = b.host,
                    .optimize = switch (config.mode) {
                        .Debug => .Debug,
                        .Release => .ReleaseFast,
                        .RelWithDebInfo => .ReleaseSafe,
                        .MinSizeRel => .ReleaseSmall,
                    },
                    .root_source_file = null,
                });

                // Add source files with C++ flags
                var cpp_flags_list = std.ArrayList([]const u8).init(b.allocator);
                defer cpp_flags_list.deinit();

                // Add user flags
                try cpp_flags_list.appendSlice(self.cpp_flags);
                
                // Add required flags
                try cpp_flags_list.append(try CppConfig.getStdFlag(b.allocator, self.cpp_std orelse CppConfig.std_version));
                try cpp_flags_list.appendSlice(&.{
                    "-fexceptions",
                    "-frtti",
                    "-D_HAS_EXCEPTIONS=1",
                });

                exe.addCSourceFiles(.{
                    .files = self.source_files,
                    .flags = try cpp_flags_list.toOwnedSlice(),
                });

                // Add include directories
                for (self.include_dirs) |dir| {
                    exe.addIncludePath(.{ .cwd_relative = dir });
                }

                // Link C++ runtime
                exe.linkLibCpp();

                try manager.addBuildCommand(build_exe, exe);
                if (last_step) |prev| {
                    try manager.addDependency(prev, build_exe);
                }
                last_step = build_exe;
                last_exe = exe;  // Store the last executable
            }
        }

        const final_step = try manager.getFinalStep();
        b.getInstallStep().dependOn(final_step);

        return last_exe orelse return error.NoExecutableBuilt;
    }
};

pub const JUCEApplication = struct {
    const Self = @This();
    
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
                const example = try app_builder.build();
                try example.build(b);
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

        pub fn build(self: *Builder) !*CppExample {
            // Create CMakeLists.txt
            const writer = try self.b.allocator.create(std.ArrayList(u8));
            writer.* = std.ArrayList(u8).init(self.b.allocator);
            defer writer.deinit();

            // Header
            try cmake.write(writer, "cmake_minimum_required(VERSION 3.15)", .{});
            try cmake.write(writer, "", .{});
            try cmake.section(writer, "project", &.{self.name, "VERSION", self.version});
            try cmake.write(writer, "add_subdirectory(deps/juce)", .{});
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
            try self.b.build_root.handle.writeFile(.{
                .sub_path = "CMakeLists.txt",
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
                .deps = &.{
                    .{
                        .name = "juce",
                        .url = "https://github.com/juce-framework/JUCE.git",
                        .include_path = "modules",
                        .type = .CMake,
                        .build_command = &.{
                            "cmd.exe", "/c",
                            "cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build --config Debug",
                        },
                    },
                },
                .configs = &.{
                    .{
                        .mode = self.build_mode,
                    },
                },
                .deps_build_system = .CMake,
                .main_build_system = .CMake,
                .cpp_std = self.cpp_std,
            };

            return example;
        }
    };

    pub fn builder(b: *std.Build) Builder {
        return Builder.init(b);
    }
};

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
        const target = b.host.query.zigTriple(b.allocator) catch "native";
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