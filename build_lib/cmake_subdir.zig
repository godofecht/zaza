//! Building an in-tree CMake subdirectory and linking it into a Zaza target.
//!
//! This is the `add_subdirectory` migration path. A project that already has a
//! CMake component in its tree (`vendor/mathlib/CMakeLists.txt`) can move its
//! top-level build to Zaza without rewriting that component: Zaza drives CMake
//! to build the subdirectory, then links the resulting library into a Zaza
//! target. The subtree stays CMake; the parent becomes Zaza.
//!
//! ```zig
//! const sub = zaza.addCMakeSubdirectory(b, .{
//!     .path = "vendor/mathlib",
//!     .lib = "mathlib",
//!     .include_dirs = &.{"vendor/mathlib/include"},
//! });
//! const exe = try zaza.Target.executable(.{ ... }).buildWithTarget(b, target);
//! sub.linkInto(exe);   // adds the built .a, its headers, and the build order
//! ```

const std = @import("std");

/// A built CMake subdirectory: the library file it produced, the headers it
/// exposes, and the build step that produces the library.
pub const CMakeSubdirectory = struct {
    lib_path: std.Build.LazyPath,
    include_dirs: []const []const u8,
    build_step: *std.Build.Step,

    /// Link this subdirectory's library into a Zaza (or plain) compile: add the
    /// built object, its public headers, and the build-order dependency so the
    /// library is built before the consumer links.
    pub fn linkInto(self: CMakeSubdirectory, compile: *std.Build.Step.Compile) void {
        compile.step.dependOn(self.build_step);
        compile.root_module.addObjectFile(self.lib_path);
        for (self.include_dirs) |dir| {
            compile.root_module.addSystemIncludePath(.{ .cwd_relative = dir });
        }
        // A C library linked into a target that may otherwise be pure Zig still
        // needs libc; requesting it here is harmless when it is already linked.
        compile.root_module.link_libc = true;
    }
};

/// How to build an in-tree CMake subdirectory.
pub const SubdirOptions = struct {
    /// Directory holding the subtree's `CMakeLists.txt`, relative to the build
    /// root.
    path: []const u8,
    /// The library target's base name, used to locate the built file
    /// (`lib<lib>.a`) unless `lib_rel` overrides it.
    lib: []const u8,
    /// Header directories the subdirectory exposes to its consumers.
    include_dirs: []const []const u8 = &.{},
    /// `CMAKE_BUILD_TYPE`. Release by default: a Debug CMake build is fine, but
    /// release keeps the linked artifact free of build-type-specific runtime
    /// dependencies.
    build_type: []const u8 = "Release",
    /// Extra `-D...` arguments passed to the configure step.
    configure_args: []const []const u8 = &.{},
    /// The built library's path relative to the CMake build directory, when it
    /// is not the default `lib<lib>.a` at the build-directory root.
    lib_rel: ?[]const u8 = null,
};

/// Configure and build a local CMake subdirectory, returning a handle that
/// links its library into a Zaza target. Configuration and build run as system
/// commands during `zig build`, so the subtree's CMake toolchain must be
/// available.
pub fn addCMakeSubdirectory(b: *std.Build, opts: SubdirOptions) CMakeSubdirectory {
    const build_dir = b.fmt(".zaza-subdir/{s}", .{opts.lib});

    var configure = b.addSystemCommand(&.{ "cmake", "-S", opts.path, "-B", build_dir });
    configure.addArg(b.fmt("-DCMAKE_BUILD_TYPE={s}", .{opts.build_type}));
    for (opts.configure_args) |arg| configure.addArg(arg);
    configure.setName(b.fmt("cmake configure {s}", .{opts.lib}));

    var build = b.addSystemCommand(&.{ "cmake", "--build", build_dir, "--config", opts.build_type });
    build.setName(b.fmt("cmake build {s}", .{opts.lib}));
    build.step.dependOn(&configure.step);

    const lib_rel = opts.lib_rel orelse b.fmt("lib{s}.a", .{opts.lib});
    const lib_path = b.path(b.fmt("{s}/{s}", .{ build_dir, lib_rel }));

    return .{
        .lib_path = lib_path,
        .include_dirs = opts.include_dirs,
        .build_step = &build.step,
    };
}
