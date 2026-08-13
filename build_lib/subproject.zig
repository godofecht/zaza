//! Composing a Zaza subproject into a parent Zaza build.
//!
//! This is the zaza-to-zaza half of `add_subdirectory`. A subdirectory keeps
//! its own `build.zig` and builds its own library targets through the Zaza
//! `Target` API. The parent build imports that `build.zig`, calls its
//! `subproject(b, target)` function, and links the exported libraries into its
//! own targets. Everything runs in one build graph, so the linked libraries and
//! their headers propagate natively.
//!
//! Subproject `build.zig`:
//!
//! ```zig
//! const zaza = @import("../../build_lib/zaza.zig");
//!
//! pub fn subproject(b: *std.Build, target: std.Build.ResolvedTarget) zaza.Subproject {
//!     const greet = zaza.Target.staticLibrary(.{
//!         .name = "greet",
//!         .source_files = &.{"libs/greet/src/greet.cpp"},
//!         .public_include_dirs = &.{"libs/greet/include"},
//!     }).buildWithTarget(b, target) catch @panic("greet: build failed");
//!
//!     return zaza.defineSubproject(b, "greet_lib", &.{
//!         .{ .name = "greet", .compile = greet, .include_dirs = &.{"libs/greet/include"} },
//!     });
//! }
//! ```
//!
//! Parent `build.zig`:
//!
//! ```zig
//! const greet_sub = @import("libs/greet/build.zig").subproject(b, target);
//! const app = try zaza.Target.executable(.{ ... }).buildWithTarget(b, target);
//! greet_sub.linkInto("greet", app);   // links the library and adds its headers
//! ```

const std = @import("std");

/// One library a subproject exposes to its parent: the built compile, the name
/// the parent refers to it by, and the header directories a consumer compiles
/// against. The include directories are build-root-relative, since a subproject
/// and its parent share one build graph.
pub const ExportedTarget = struct {
    name: []const u8,
    compile: *std.Build.Step.Compile,
    include_dirs: []const []const u8 = &.{},
};

/// A composed subproject: a name and the library targets it exposes. Returned
/// by a subproject's `subproject(b, target)` function via `defineSubproject`.
pub const Subproject = struct {
    name: []const u8,
    targets: []const ExportedTarget,

    /// The exported compile named `name`, or a panic naming the miss. Use this
    /// when a consumer needs the artifact directly rather than through
    /// `linkInto`.
    pub fn artifact(self: Subproject, name: []const u8) *std.Build.Step.Compile {
        return self.find(name).compile;
    }

    /// Link the exported library named `name` into `consumer`: link the library
    /// and add its exported header directories so the consumer compiles against
    /// them. Both targets must have been built for the same resolved target.
    pub fn linkInto(self: Subproject, name: []const u8, consumer: *std.Build.Step.Compile) void {
        const t = self.find(name);
        const b = consumer.step.owner;
        consumer.root_module.linkLibrary(t.compile);
        for (t.include_dirs) |dir| {
            consumer.root_module.addIncludePath(b.path(dir));
        }
    }

    fn find(self: Subproject, name: []const u8) ExportedTarget {
        for (self.targets) |t| {
            if (std.mem.eql(u8, t.name, name)) return t;
        }
        std.debug.panic(
            "subproject '{s}' exposes no target named '{s}'",
            .{ self.name, name },
        );
    }
};

/// Define a subproject from its exposed library targets. The subproject's
/// `build.zig` calls this after building its targets and returns the result to
/// the parent.
pub fn defineSubproject(
    b: *std.Build,
    name: []const u8,
    targets: []const ExportedTarget,
) Subproject {
    // Copy the targets onto the build allocator. A subproject's `build.zig`
    // passes an array literal (`&.{ ... }`), which is a temporary in that
    // function; the returned Subproject outlives it, so it must own its slice.
    // The inner strings and the compile pointers are stable already.
    const owned = b.allocator.dupe(ExportedTarget, targets) catch @panic("OOM");
    return .{ .name = name, .targets = owned };
}
