//! A Zaza subproject: it owns this `build.zig` and its `greet` library, and
//! exposes that library to a parent build through `subproject`.
//!
//! Paths are relative to the root build directory, because a composed
//! subproject shares the parent's build graph. `build` lets the subproject be
//! configured on its own; `subproject` is what the parent calls.

const std = @import("std");
const zaza = @import("../../../../build_lib/zaza.zig");

pub fn subproject(b: *std.Build, target: std.Build.ResolvedTarget) zaza.Subproject {
    const greet = zaza.Target.staticLibrary(.{
        .name = "greet",
        .description = "a small greeting library, built as a zaza subproject",
        .source_files = &.{"examples/zaza_subproject/libs/greet/src/greet.cpp"},
        .public_include_dirs = &.{"examples/zaza_subproject/libs/greet/include"},
        .cpp_std = "17",
        .configs = zaza.config_sets.release_only,
    }).buildWithTarget(b, target) catch @panic("greet subproject: build failed");

    return zaza.defineSubproject(b, "greet_lib", &.{
        .{
            .name = "greet",
            .compile = greet,
            .include_dirs = &.{"examples/zaza_subproject/libs/greet/include"},
        },
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    _ = subproject(b, target);
}
