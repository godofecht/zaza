const std = @import("std");
const fs = std.fs;
const mem = std.mem;

pub const Dependency = struct {
    url: []const u8,
    rev: []const u8,
    name: []const u8,
    cmake_package: ?[]const u8 = null,
    subdirectory: ?[]const u8 = null,
    include_path: ?[]const u8 = null,
};

pub const DependencyManager = struct {
    allocator: mem.Allocator,
    deps_dir: []const u8,
    workspace_root: []const u8,
    dependencies: std.ArrayList(Dependency),
    cmake_paths: std.ArrayList([]const u8),

    pub fn init(allocator: mem.Allocator) DependencyManager {
        return initWithPaths(allocator, "deps", ".");
    }

    pub fn initWithPaths(allocator: mem.Allocator, deps_dir: []const u8, workspace_root: []const u8) DependencyManager {
        return .{
            .allocator = allocator,
            .deps_dir = deps_dir,
            .workspace_root = workspace_root,
            .dependencies = std.ArrayList(Dependency).init(allocator),
            .cmake_paths = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn resolvePath(self: *DependencyManager, components: []const []const u8) ![]const u8 {
        // If first component is absolute, just join the rest
        if (fs.path.isAbsolute(components[0])) {
            return fs.path.join(self.allocator, components);
        }
        
        // Otherwise join with workspace root first
        var with_root = try std.ArrayList([]const u8).initCapacity(self.allocator, components.len + 1);
        defer with_root.deinit();
        
        try with_root.append(self.workspace_root);
        try with_root.appendSlice(components);
        
        return fs.path.join(self.allocator, with_root.items);
    }

    pub fn deinit(self: *DependencyManager) void {
        for (self.cmake_paths.items) |path| {
            self.allocator.free(path);
        }
        self.cmake_paths.deinit();
        self.dependencies.deinit();
    }

    pub fn add(self: *DependencyManager, dep: Dependency) !void {
        try self.dependencies.append(dep);
    }

    pub fn fetch(self: *DependencyManager) !void {
        // Create deps directory if it doesn't exist
        try fs.cwd().makePath(self.deps_dir);

        for (self.dependencies.items) |dep| {
            const dep_path = try fs.path.join(
                self.allocator,
                &[_][]const u8{ self.deps_dir, dep.name }
            );
            defer self.allocator.free(dep_path);

            // Check if directory exists
            if (fs.cwd().statFile(dep_path)) |_| {
                // Directory exists, skip cloning
            } else |_| {
                try self.cloneDependency(dep, dep_path);
            }

            // Process CMake files if needed
            if (dep.cmake_package != null or dep.subdirectory != null) {
                try self.processCMakeFiles(dep, dep_path);
            }
        }
    }

    fn cloneDependency(self: *DependencyManager, dep: Dependency, dep_path: []const u8) !void {
        std.debug.print("Cloning {s} from {s}...\n", .{ dep.name, dep.url });
        
        const git_clone = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "git",
                "clone",
                "--progress",
                dep.url,
                dep_path,
            },
        });
        std.debug.print("Clone output: {s}\n", .{git_clone.stdout});
        
        std.debug.print("Checking out {s}...\n", .{dep.rev});
        const git_checkout = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "git",
                "-C",
                dep_path,
                "checkout",
                dep.rev,
            },
        });
        std.debug.print("Checkout output: {s}\n", .{git_checkout.stdout});
    }

    fn processCMakeFiles(self: *DependencyManager, dep: Dependency, dep_path: []const u8) !void {
        if (dep.cmake_package) |_| {
            const cmake_path = try fs.path.join(
                self.allocator,
                &[_][]const u8{ dep_path, "cmake" }
            );
            try self.cmake_paths.append(cmake_path);
        }

        if (dep.subdirectory) |subdir| {
            const subdir_path = try fs.path.join(
                self.allocator,
                &[_][]const u8{ dep_path, subdir }
            );
            defer self.allocator.free(subdir_path);

            const cmake_file = try fs.path.join(
                self.allocator,
                &[_][]const u8{ subdir_path, "CMakeLists.txt" }
            );
            defer self.allocator.free(cmake_file);
        }
    }

    pub fn getIncludePaths(self: *DependencyManager) ![]const []const u8 {
        var paths = std.ArrayList([]const u8).init(self.allocator);
        errdefer paths.deinit();

        for (self.dependencies.items) |dep| {
            if (dep.include_path) |include_path| {
                const full_path = try self.resolvePath(&.{ 
                    self.deps_dir, 
                    dep.name, 
                    include_path 
                });
                try paths.append(full_path);
            }
        }

        return paths.toOwnedSlice();
    }

    pub fn getCMakePaths(self: *DependencyManager) []const []const u8 {
        return self.cmake_paths.items;
    }

    pub fn fetchLatest(self: *DependencyManager, repo: []const u8) !Dependency {
        // Parse repo format: "owner/name[@version]"
        var parts = std.mem.split(u8, repo, "@");
        const repo_part = parts.next() orelse return error.InvalidRepo;
        const version = parts.next();  // Optional version tag

        var repo_parts = std.mem.split(u8, repo_part, "/");
        _ = repo_parts.next() orelse return error.InvalidRepo;  // owner
        const name = repo_parts.next() orelse return error.InvalidRepo;

        const rev = if (version) |v| 
            try std.fmt.allocPrint(self.allocator, "v{s}", .{v}) 
        else 
            "main";
        
        return .{
            .url = try std.fmt.allocPrint(self.allocator, "https://github.com/{s}", .{repo_part}),
            .rev = rev,
            .name = name,
            .cmake_package = if (std.mem.eql(u8, name, "json")) "nlohmann_json" else null,
            .include_path = if (std.mem.eql(u8, name, "json")) "single_include" else null,
        };
    }
}; 