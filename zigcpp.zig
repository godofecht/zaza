const std = @import("std");
const deps = @import("dependencies.zig");

pub const build = struct {
    pub fn init(comptime steps: anytype) type {
        return struct {
            pub fn build(b: *std.Build) !void {
                var app = Cpp.create(b, "cpp-program", .executable);
                defer app.deinit();
                
                inline for (steps) |step| {
                    _ = @call(.auto, step, .{&app});
                }
                
                try app.build();
            }
        };
    }
};

pub const Cpp = struct {
    const Target = enum { executable, library, shared };
    const Self = @This();
    const Source = struct { path: []const u8, flags: ?[]const []const u8 = null };
    const Error = error{
        DependencyError,
        SourceError,
        BuildError,
    };

    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    dependencies: deps.DependencyManager,
    source_list: std.ArrayList(Source),
    version: []const u8 = "17",
    errors: std.ArrayList(Error),
    is_cmake_build: bool = false,

    pub fn makeCmake(b: *std.Build) !void {
        var app = b.addExecutable(.{
            .name = "cpp-program",
            .root_source_file = null,
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        });
        try app.generateCMake();
    }

    pub fn create(b: *std.Build, name: []const u8, target: Target) Self {
        var cpp = createWithOptions(b, name, target, b.standardTargetOptions(.{}), b.standardOptimizeOption(.{}));
        // Initialize with build root for proper path resolution
        cpp.dependencies = deps.DependencyManager.initWithPaths(
            b.allocator,
            "deps",
            b.build_root.path.?
        );
        return cpp;
    }

    pub fn createWithOptions(
        b: *std.Build,
        name: []const u8,
        target_type: Target,
        target: std.zig.CrossTarget,
        optimize: std.builtin.OptimizeMode,
    ) Self {
        return .{
            .b = b,
            .artifact = switch (target_type) {
                .executable => b.addExecutable(.{
                    .name = name,
                    .target = target,
                    .optimize = optimize,
                }),
                .library => b.addStaticLibrary(.{
                    .name = name,
                    .target = target,
                    .optimize = optimize,
                }),
                .shared => b.addSharedLibrary(.{
                    .name = name,
                    .target = target,
                    .optimize = optimize,
                }),
            },
            .dependencies = deps.DependencyManager.init(b.allocator),
            .source_list = std.ArrayList(Source).init(b.allocator),
            .errors = std.ArrayList(Error).init(b.allocator),
        };
    }

    pub fn deinit(self: *Self) void { 
        self.source_list.deinit(); 
        self.dependencies.deinit(); 
        self.errors.deinit();
    }

    pub fn standard(self: *Self, ver: []const u8) *Self { 
        self.version = ver; 
        return self; 
    }

    pub fn include(self: *Self, dir: []const u8) *Self {
        return self.includes(&.{dir});
    }

    pub fn includes(self: *Self, dirs: []const []const u8) *Self {
        for (dirs) |dir| {
            self.artifact.addIncludePath(.{.path = dir});
        }
        return self;
    }

    pub fn library(self: *Self, lib: []const u8) *Self {
        return self.libraries(&.{lib});
    }

    pub fn libraries(self: *Self, libs: []const []const u8) *Self {
        for (libs) |lib| {
            self.artifact.linkSystemLibrary(lib);
        }
        return self;
    }

    pub fn addArtifact(self: *Self, artifact: *std.Build.Step.Compile) *Self {
        self.artifact.linkLibrary(artifact);
        return self;
    }

    pub fn define(self: *Self, macro: []const u8) *Self {
        if (std.mem.eql(u8, macro, "CMAKE_BUILD")) {
            self.is_cmake_build = true;
        }
        self.artifact.defineCMacro(macro, null);
        return self;
    }

    pub fn defines(self: *Self, macros: []const []const u8) *Self {
        for (macros) |macro| {
            _ = self.define(macro);
        }
        return self;
    }

    // Error returning operations
    pub fn addDependency(self: *Self, dep: deps.Dependency) !*Self {
        try self.dependencies.add(dep);
        return self;
    }

    pub fn addSource(self: *Self, file: []const u8) *Self {
        return self.addSources(&.{file});
    }

    pub fn addSources(self: *Self, files: []const []const u8) *Self {
        for (files) |file| {
            self.source_list.append(.{ .path = file }) catch |err| {
                std.debug.print("Error adding source {s}: {any}\n", .{file, err});
                self.errors.append(Error.SourceError) catch {};
            };
        }
        return self;
    }

    pub fn addGithubDependency(self: *Self, repo: []const u8) *Self {
        const dep = self.dependencies.fetchLatest(repo) catch |err| {
            std.debug.print("Error fetching dependency {s}: {any}\n", .{repo, err});
            self.errors.append(Error.DependencyError) catch {};
            return self;
        };
        self.dependencies.add(dep) catch |err| {
            std.debug.print("Error adding dependency {s}: {any}\n", .{repo, err});
            self.errors.append(Error.DependencyError) catch {};
        };
        return self;
    }

    pub fn build(self: *Self) !void {
        // Check for buffered errors
        if (self.errors.items.len > 0) {
            std.debug.print("Found {d} errors during build setup\n", .{self.errors.items.len});
            return error.BuildError;
        }

        std.debug.print("Building {s}...\n", .{self.artifact.name});
        try self.dependencies.fetch();

        // Check if this is a CMake build
        if (self.is_cmake_build) {
            try self.buildWithCMake();
            return;
        }
        
        const std_flag = try std.fmt.allocPrint(self.b.allocator, "-std=c++{s}", .{self.version});
        defer self.b.allocator.free(std_flag);

        // Add C++ standard library paths
        self.artifact.linkLibCpp();

        // Add include paths from dependencies
        for (try self.dependencies.getIncludePaths()) |path| {
            self.artifact.addIncludePath(.{.path = path});
        }

        // Add source files
        std.debug.print("Adding source files...\n", .{});
        for (self.source_list.items) |source| {
            std.debug.print("  {s}\n", .{source.path});
            self.artifact.addCSourceFile(.{
                .file = .{ .path = source.path },
                .flags = &.{std_flag},
            });
        }

        std.debug.print("Installing to zig-out/bin/\n", .{});
        self.b.installArtifact(self.artifact);
    }

    fn buildWithCMake(self: *Self) !void {
        // Create build directory
        const build_dir = try std.fmt.allocPrint(self.b.allocator, "zig-cache/cmake/{s}", .{self.artifact.name});
        defer self.b.allocator.free(build_dir);
        try std.fs.cwd().makePath(build_dir);

        // Run CMake configure
        var cmake_configure = std.ChildProcess.init(&.{
            "cmake",
            "-S", ".",
            "-B", build_dir,
            "-DCMAKE_BUILD_TYPE=Debug",
        }, self.b.allocator);
        _ = try cmake_configure.spawnAndWait();

        // Run CMake build
        var cmake_build = std.ChildProcess.init(&.{
            "cmake",
            "--build", build_dir,
            "--config", "Debug",
        }, self.b.allocator);
        _ = try cmake_build.spawnAndWait();

        // Add built library to artifact
        const lib_path = try std.fmt.allocPrint(self.b.allocator, "{s}/lib{s}.a", .{build_dir, self.artifact.name});
        defer self.b.allocator.free(lib_path);
        self.artifact.addObjectFile(.{ .path = lib_path });
    }

    pub fn generateCMake(self: *Self) !void {
        const allocator = self.b.allocator;
        const cmake_content = try std.fmt.allocPrint(allocator,
            \\cmake_minimum_required(VERSION 3.15)
            \\project({s} LANGUAGES CXX)
            \\
            \\set(CMAKE_CXX_STANDARD {s})
            \\set(CMAKE_CXX_STANDARD_REQUIRED ON)
            \\
            \\add_executable({s}
            \\{s}
            \\)
            \\
            \\target_compile_definitions({s} PRIVATE
            \\    VERSION="${s}"
            \\)
            \\
            \\target_include_directories({s} PRIVATE
            \\    include
            \\)
            \\
            \\find_package(nlohmann_json REQUIRED)
            \\target_link_libraries({s} PRIVATE
            \\    nlohmann_json::nlohmann_json
            \\)
            \\
        , .{
            self.artifact.name,
            self.version,
            self.artifact.name,
            try self.formatSourceList(),
            self.artifact.name,
            "1.0.0",
            self.artifact.name,
            self.artifact.name,
        });
        defer allocator.free(cmake_content);

        // Create zig-out/bin directory if it doesn't exist
        try std.fs.cwd().makePath("zig-out/bin");
        
        // Write CMakeLists.txt to zig-out/bin
        try std.fs.cwd().writeFile("zig-out/bin/CMakeLists.txt", cmake_content);
        std.debug.print("Generated zig-out/bin/CMakeLists.txt\n", .{});
    }

    fn formatSourceList(self: *Self) ![]const u8 {
        var list = std.ArrayList(u8).init(self.b.allocator);
        defer list.deinit();

        for (self.source_list.items) |src| {
            try list.writer().print("    {s}\n", .{src.path});
        }
        return list.toOwnedSlice();
    }

    pub fn setDepsDir(self: *Self, dir: []const u8) void {
        self.dependencies = deps.DependencyManager.initWithPaths(
            self.b.allocator,
            dir,
            self.b.build_root.path.?
        );
    }
}; 