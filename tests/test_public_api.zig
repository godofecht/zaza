const std = @import("std");
const testing = std.testing;
const zaza = @import("zaza");

// These tests exercise the public facade on its own. They assert that every
// re-exported name resolves and behaves, so the stable surface cannot silently
// lose a declaration. They deliberately do not compare types against a second,
// separately imported copy of the underlying module: two independently added
// modules of the same file are distinct instances, so such a comparison would
// test module identity rather than the facade.

test "target constructors are reachable and set the kind" {
    const exe = zaza.Target.executable(.{
        .name = "facade_app",
        .source_files = &.{"src/main.cpp"},
        .include_dirs = &.{},
        .cpp_flags = &.{},
        .deps = &.{},
    });
    try testing.expectEqualStrings("facade_app", exe.name);
    try testing.expectEqual(zaza.TargetKind.executable, exe.kind);

    const lib = zaza.Target.staticLibrary(.{
        .name = "facade_lib",
        .source_files = &.{"src/lib.cpp"},
        .include_dirs = &.{},
        .cpp_flags = &.{},
        .deps = &.{},
    });
    try testing.expectEqual(zaza.TargetKind.static_library, lib.kind);
}

test "CppExample alias still constructs, for backward compatibility" {
    const exe = zaza.CppExample.executable(.{
        .name = "legacy_app",
        .source_files = &.{"src/main.cpp"},
        .include_dirs = &.{},
        .cpp_flags = &.{},
        .deps = &.{},
    });
    try testing.expectEqualStrings("legacy_app", exe.name);
}

test "named configurations resolve" {
    try testing.expectEqual(zaza.BuildMode.Debug, zaza.configs.Debug.mode);
    try testing.expectEqual(zaza.BuildMode.Release, zaza.configs.Release.mode);
    try testing.expect(zaza.config_sets.debug_release.len == 2);
}

test "preset resolution is reachable through the facade" {
    const release = zaza.presetConfigs("release");
    try testing.expectEqual(@as(usize, 1), release.len);
    try testing.expectEqual(zaza.BuildMode.Release, release[0].mode);

    const unknown = zaza.presetConfigs("does-not-exist");
    try testing.expectEqual(zaza.BuildMode.Debug, unknown[0].mode);
}

test "dependency and define helpers are reachable" {
    const dep = zaza.Dependency{ .name = "fmt", .url = "https://github.com/fmtlib/fmt" };
    try testing.expectEqualStrings("fmt", dep.name);
    try testing.expect(zaza.Defines.release.len > 0);
}

test "command hint is reachable through the facade" {
    try testing.expect(zaza.commandHint(&.{"git"}) != null);
    try testing.expect(zaza.commandHint(&.{"ls"}) == null);
}

test "the build-graph entry points are present with the right signatures" {
    // Reference these by type, not by value. Taking their value would force the
    // compiler to analyse the function bodies, which reach the build graph's
    // lazy-dependency machinery (`b.dependency`). That machinery needs the build
    // runner's root and cannot compile under the plain unit-test runner, so a
    // signature check is the right depth here.
    try testing.expect(@hasDecl(zaza, "addTest"));
    try testing.expect(@hasDecl(zaza, "addBench"));
    try testing.expect(@hasDecl(zaza, "addCommandStep"));
    try testing.expect(@hasDecl(zaza, "envString"));
    // Naming the type resolves each alias to a real symbol without analysing the
    // body. Kept as statements so the compiler cannot fold them away.
    _ = @TypeOf(zaza.addTest);
    _ = @TypeOf(zaza.addBench);
    _ = @TypeOf(zaza.addCommandStep);
    _ = @TypeOf(zaza.envString);
}

test "the re-exported option and result types are present" {
    // Naming the types is enough to confirm the facade exposes them; none of
    // this analyses a build-graph function body.
    try testing.expect(@hasDecl(zaza, "TargetOptions"));
    try testing.expect(@hasDecl(zaza, "TestOptions"));
    try testing.expect(@hasDecl(zaza, "BenchOptions"));
    try testing.expect(@hasDecl(zaza, "SuiteResult"));
    try testing.expect(@hasDecl(zaza, "RunCase"));
    try testing.expect(@hasDecl(zaza, "EnvVar"));
    try testing.expect(@hasDecl(zaza, "RustExample"));
    try testing.expect(@hasDecl(zaza, "JUCEApplication"));
    try testing.expect(@hasDecl(zaza, "CMakeConfig"));
    try testing.expect(@hasDecl(zaza, "Deps"));
    try testing.expect(@hasDecl(zaza, "CppTarget"));
    try testing.expect(@hasDecl(zaza, "TargetDependency"));
    try testing.expect(@hasDecl(zaza, "ResolvedUsage"));
    const opts: zaza.RunCase = .{ .label = "unit" };
    try testing.expectEqualStrings("unit", opts.label);
}
