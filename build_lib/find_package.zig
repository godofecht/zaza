//! Package discovery: resolve an already-installed C/C++ library into the
//! include dirs, defines, and link inputs a target needs, without hand-wiring
//! paths. This is Zaza's answer to CMake's `find_package` and to pkg-config.
//!
//! It does not reimplement either resolver. It asks the real ones. `pkg-config`
//! is queried directly; a CMake package is resolved by generating a throwaway
//! probe project that runs `find_package(<name> REQUIRED)` and writes the
//! resolved variables back out. Whatever the installed `.pc` file or `Find`/
//! `Config` module reports is what a Zaza target links against. That keeps Zaza
//! compatible with the installed ecosystem instead of guessing at it.
//!
//! Resolution runs at configure time (while `build.zig` executes), the same
//! point CMake resolves `find_package`, so the flags are known before the
//! compile step is created.
//!
//! ```zig
//! const zlib = zaza.findPackage(b, "zlib", .{});           // pkg-config or CMake
//! const app = zaza.Target.executable(.{
//!     .name = "app",
//!     .source_files = &.{"src/main.c"},
//!     .c_std = "11",
//!     .packages = &.{zlib},                                 // include dirs + libs folded in
//! });
//! ```

const std = @import("std");

/// Which resolver produced a package's flags.
pub const Source = enum { manual, pkg_config, cmake };

/// A resolved package: the compile and link inputs an installed library
/// contributes to a target. Every list is already stripped of its flag prefix
/// (`include_dirs` hold plain paths, `defines` hold `FOO=1`, `link_libs` hold
/// `z`), so the build applies them through the same module calls it uses for
/// first-party settings.
pub const ResolvedPackage = struct {
    name: []const u8,
    found: bool = false,
    version: ?[]const u8 = null,
    source: Source = .manual,
    /// Header search paths (added as system include paths).
    include_dirs: []const []const u8 = &.{},
    /// Preprocessor definitions, without the `-D` prefix (`FOO` or `FOO=1`).
    defines: []const []const u8 = &.{},
    /// Other compile flags to pass verbatim (e.g. `-pthread`).
    cflags: []const []const u8 = &.{},
    /// Library search paths (`-L`).
    link_paths: []const []const u8 = &.{},
    /// System libraries by name, without the `-l` prefix (`z`, `curl`).
    link_libs: []const []const u8 = &.{},
    /// Fully qualified library files to link (absolute `.a` / `.dylib` / `.so`).
    link_files: []const []const u8 = &.{},
    /// macOS frameworks to link (`-framework Foo`).
    frameworks: []const []const u8 = &.{},
};

/// Which resolver to consult. `auto` tries pkg-config first, then CMake.
pub const Prefer = enum { auto, pkg_config, cmake };

/// How to resolve a package. Defaults find a required package by its own name
/// through either resolver.
pub const FindOptions = struct {
    /// Minimum acceptable version (`pkg-config --atleast-version`, CMake
    /// `find_package(<name> <version>)`). Null accepts any installed version.
    version: ?[]const u8 = null,
    /// Fail the build when the package is not found. Set false to allow an
    /// optional dependency; the returned package then has `found = false`.
    required: bool = true,
    /// Which resolver(s) to try.
    prefer: Prefer = .auto,
    /// The `.pc` module name, when it differs from `name`.
    pkg_config_name: ?[]const u8 = null,
    /// The `find_package(<...>)` name, when it differs from `name`
    /// (CMake package names are case-sensitive: `ZLIB`, `CURL`, `OpenSSL`).
    cmake_name: ?[]const u8 = null,
    /// An imported target to read precise usage requirements from
    /// (`ZLIB::ZLIB`, `CURL::libcurl`). Needed for config packages that export
    /// only an imported target and set no `<pkg>_LIBRARIES` variable.
    cmake_target: ?[]const u8 = null,
};

/// Resolve `name` into a `ResolvedPackage`. Panics if the package is required
/// and no resolver finds it; returns `found = false` if it is optional.
pub fn findPackage(b: *std.Build, name: []const u8, opts: FindOptions) ResolvedPackage {
    const try_pc = opts.prefer != .cmake;
    const try_cm = opts.prefer != .pkg_config;

    if (try_pc) {
        if (viaPkgConfig(b, name, opts)) |pkg| return pkg;
    }
    if (try_cm) {
        if (viaCMake(b, name, opts)) |pkg| return pkg;
    }

    if (opts.required) {
        std.debug.panic(
            "zaza.findPackage: required package '{s}' not found via {s}. " ++
                "Install it so pkg-config sees its .pc file or CMake sees a Find/Config module, " ++
                "or pass .{{ .required = false }}.",
            .{ name, preferLabel(opts.prefer) },
        );
    }
    return .{ .name = name, .found = false };
}

fn preferLabel(prefer: Prefer) []const u8 {
    return switch (prefer) {
        .auto => "pkg-config or CMake",
        .pkg_config => "pkg-config",
        .cmake => "CMake",
    };
}

/// Run a command, returning captured stdout on a clean (exit 0) run, or null if
/// the tool is missing or exits non-zero. `runAllowFail` returns
/// `error.ExitCodeFailure` on a non-zero exit, so a missing tool and an absent
/// package both surface here as null.
fn run(b: *std.Build, argv: []const []const u8) ?[]u8 {
    var code: u8 = 0;
    return b.runAllowFail(argv, &code, .Ignore) catch null;
}

const StrList = std.ArrayListUnmanaged([]const u8);

fn hasLibExt(path: []const u8) bool {
    const exts = [_][]const u8{ ".a", ".dylib", ".tbd", ".lib" };
    for (exts) |e| {
        if (std.mem.endsWith(u8, path, e)) return true;
    }
    // .so, .so.1, .so.1.2 ...
    if (std.mem.indexOf(u8, path, ".so") != null) return true;
    return false;
}

// --- pkg-config ---------------------------------------------------------------

fn viaPkgConfig(b: *std.Build, name: []const u8, opts: FindOptions) ?ResolvedPackage {
    const pc = opts.pkg_config_name orelse name;

    if (opts.version) |v| {
        if (run(b, &.{ "pkg-config", b.fmt("--atleast-version={s}", .{v}), pc }) == null) return null;
    } else {
        if (run(b, &.{ "pkg-config", "--exists", pc }) == null) return null;
    }

    var pkg = ResolvedPackage{ .name = name, .found = true, .source = .pkg_config };
    if (run(b, &.{ "pkg-config", "--modversion", pc })) |mv| {
        pkg.version = b.dupe(std.mem.trim(u8, mv, " \t\r\n"));
    }

    var inc: StrList = .empty;
    var def: StrList = .empty;
    var cf: StrList = .empty;
    var lp: StrList = .empty;
    var ll: StrList = .empty;
    var lf: StrList = .empty;
    var fw: StrList = .empty;

    if (run(b, &.{ "pkg-config", "--cflags", pc })) |out| parseCflags(b, out, &inc, &def, &cf);
    if (run(b, &.{ "pkg-config", "--libs", pc })) |out| parseLibs(b, out, &lp, &ll, &lf, &fw);

    pkg.include_dirs = inc.toOwnedSlice(b.allocator) catch &.{};
    pkg.defines = def.toOwnedSlice(b.allocator) catch &.{};
    pkg.cflags = cf.toOwnedSlice(b.allocator) catch &.{};
    pkg.link_paths = lp.toOwnedSlice(b.allocator) catch &.{};
    pkg.link_libs = ll.toOwnedSlice(b.allocator) catch &.{};
    pkg.link_files = lf.toOwnedSlice(b.allocator) catch &.{};
    pkg.frameworks = fw.toOwnedSlice(b.allocator) catch &.{};
    return pkg;
}

fn parseCflags(b: *std.Build, out: []const u8, inc: *StrList, def: *StrList, cf: *StrList) void {
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-I")) {
            const dir = tok[2..];
            if (dir.len > 0) inc.append(b.allocator, b.dupe(dir)) catch {};
        } else if (std.mem.startsWith(u8, tok, "-D")) {
            def.append(b.allocator, b.dupe(tok[2..])) catch {};
        } else if (std.mem.eql(u8, tok, "-isystem")) {
            if (it.next()) |dir| inc.append(b.allocator, b.dupe(dir)) catch {};
        } else {
            cf.append(b.allocator, b.dupe(tok)) catch {};
        }
    }
}

fn parseLibs(b: *std.Build, out: []const u8, lp: *StrList, ll: *StrList, lf: *StrList, fw: *StrList) void {
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    while (it.next()) |tok| {
        if (std.mem.eql(u8, tok, "-framework")) {
            if (it.next()) |name| fw.append(b.allocator, b.dupe(name)) catch {};
        } else if (std.mem.startsWith(u8, tok, "-L")) {
            lp.append(b.allocator, b.dupe(tok[2..])) catch {};
        } else if (std.mem.startsWith(u8, tok, "-l")) {
            ll.append(b.allocator, b.dupe(tok[2..])) catch {};
        } else if (tok.len > 0 and tok[0] == '/' and hasLibExt(tok)) {
            lf.append(b.allocator, b.dupe(tok)) catch {};
        }
        // Other tokens (-Wl,..., -pthread on the link line) are left out: the
        // -pthread compile flag already comes through --cflags, and rpath-style
        // linker flags are not needed to link these libraries.
    }
}

// --- CMake (used as the resolver oracle) --------------------------------------

/// Zig 0.16 moved the filesystem under std.Io. Only the taken branch is
/// analysed, so each spelling is compiled on the version that has it.
fn makeBuildRootPath(b: *std.Build, sub_path: []const u8) void {
    if (comptime @hasDecl(std.fs, "cwd")) {
        b.build_root.handle.makePath(sub_path) catch {};
    } else {
        b.build_root.handle.makePath(b.graph.io, sub_path) catch {};
    }
}

fn readBuildRootFile(b: *std.Build, sub_path: []const u8) ?[]u8 {
    if (comptime @hasDecl(std.fs, "cwd")) {
        return b.build_root.handle.readFileAlloc(b.allocator, sub_path, 4 * 1024 * 1024) catch null;
    } else {
        return b.build_root.handle.readFileAlloc(b.graph.io, sub_path, b.allocator, .unlimited) catch null;
    }
}

fn writeBuildRootFile(b: *std.Build, sub_path: []const u8, data: []const u8) bool {
    if (comptime @hasDecl(std.fs, "cwd")) {
        b.build_root.handle.writeFile(.{ .sub_path = sub_path, .data = data }) catch return false;
    } else {
        b.build_root.handle.writeFile(b.graph.io, .{ .sub_path = sub_path, .data = data }) catch return false;
    }
    return true;
}

fn viaCMake(b: *std.Build, name: []const u8, opts: FindOptions) ?ResolvedPackage {
    if (run(b, &.{ "cmake", "--version" }) == null) return null; // cmake absent

    const cm_name = opts.cmake_name orelse name;
    const ver = opts.version orelse "";
    const target = opts.cmake_target orelse "";
    const dir = b.fmt(".zaza-find/{s}", .{cm_name});
    makeBuildRootPath(b, dir);

    // Probe project: resolve the package with CMake's own machinery, then write
    // the resolved module variables and (when an imported target is named) its
    // precise interface properties to files we read back.
    const cml = b.fmt(
        \\cmake_minimum_required(VERSION 3.15)
        \\project(zaza_find C)
        \\find_package({s} {s} REQUIRED)
        \\set(_t "{s}")
        \\if(_t AND TARGET ${{_t}})
        \\  file(GENERATE OUTPUT "${{CMAKE_BINARY_DIR}}/target.txt" CONTENT "INCLUDE_DIRS=$<TARGET_PROPERTY:${{_t}},INTERFACE_INCLUDE_DIRECTORIES>\nDEFINITIONS=$<TARGET_PROPERTY:${{_t}},INTERFACE_COMPILE_DEFINITIONS>\nLINK=$<TARGET_LINKER_FILE:${{_t}}>\n")
        \\endif()
        \\file(WRITE "${{CMAKE_BINARY_DIR}}/module.txt" "VERSION=${{{s}_VERSION}}\nINCLUDE_DIRS=${{{s}_INCLUDE_DIRS}}\nLIBRARIES=${{{s}_LIBRARIES}}\nDEFINITIONS=${{{s}_DEFINITIONS}}\n")
        \\
    , .{ cm_name, ver, target, cm_name, cm_name, cm_name, cm_name });

    if (!writeBuildRootFile(b, b.fmt("{s}/CMakeLists.txt", .{dir}), cml)) return null;

    const bdir = b.fmt("{s}/build", .{dir});
    // A REQUIRED find_package that fails makes configure exit non-zero, so a
    // null here means "not found" as well as "cmake errored".
    if (run(b, &.{ "cmake", "-S", dir, "-B", bdir }) == null) return null;

    var pkg = ResolvedPackage{ .name = name, .found = true, .source = .cmake };
    var inc: StrList = .empty;
    var def: StrList = .empty;
    var lp: StrList = .empty;
    var ll: StrList = .empty;
    var lf: StrList = .empty;
    var fw: StrList = .empty;

    // Module variables first (covers every builtin Find module: ZLIB, CURL,
    // OpenSSL, PNG, JPEG, Threads, ...).
    if (readBuildRootFile(b, b.fmt("{s}/module.txt", .{bdir}))) |txt| {
        var lines = std.mem.tokenizeScalar(u8, txt, '\n');
        while (lines.next()) |line| {
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = line[0..eq];
            const val = std.mem.trim(u8, line[eq + 1 ..], " \t\r");
            if (val.len == 0) continue;
            if (std.mem.eql(u8, key, "VERSION")) {
                pkg.version = b.dupe(val);
            } else if (std.mem.eql(u8, key, "INCLUDE_DIRS")) {
                appendCMakeList(b, val, &inc);
            } else if (std.mem.eql(u8, key, "LIBRARIES")) {
                classifyCMakeLibs(b, val, &ll, &lf, &fw);
            } else if (std.mem.eql(u8, key, "DEFINITIONS")) {
                appendDefines(b, val, &def);
            }
        }
    }

    // Precise imported-target properties override the module guesses when a
    // target was named (needed for config packages that set no module vars).
    if (target.len != 0) {
        if (readBuildRootFile(b, b.fmt("{s}/target.txt", .{bdir}))) |txt| {
            var lines = std.mem.tokenizeScalar(u8, txt, '\n');
            while (lines.next()) |line| {
                const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
                const key = line[0..eq];
                const val = std.mem.trim(u8, line[eq + 1 ..], " \t\r");
                if (val.len == 0) continue;
                if (std.mem.eql(u8, key, "INCLUDE_DIRS")) {
                    inc = .empty;
                    appendCMakeList(b, val, &inc);
                } else if (std.mem.eql(u8, key, "DEFINITIONS")) {
                    def = .empty;
                    appendDefines(b, val, &def);
                } else if (std.mem.eql(u8, key, "LINK")) {
                    if (val[0] == '/' and hasLibExt(val)) {
                        lf = .empty;
                        lf.append(b.allocator, b.dupe(val)) catch {};
                    }
                }
            }
        }
    }

    pkg.include_dirs = inc.toOwnedSlice(b.allocator) catch &.{};
    pkg.defines = def.toOwnedSlice(b.allocator) catch &.{};
    pkg.link_paths = lp.toOwnedSlice(b.allocator) catch &.{};
    pkg.link_libs = ll.toOwnedSlice(b.allocator) catch &.{};
    pkg.link_files = lf.toOwnedSlice(b.allocator) catch &.{};
    pkg.frameworks = fw.toOwnedSlice(b.allocator) catch &.{};
    return pkg;
}

fn appendCMakeList(b: *std.Build, val: []const u8, out: *StrList) void {
    var it = std.mem.tokenizeScalar(u8, val, ';');
    while (it.next()) |item| {
        const t = std.mem.trim(u8, item, " \t\r");
        if (t.len > 0) out.append(b.allocator, b.dupe(t)) catch {};
    }
}

fn appendDefines(b: *std.Build, val: []const u8, out: *StrList) void {
    var it = std.mem.tokenizeAny(u8, val, "; \t");
    while (it.next()) |item| {
        const d = if (std.mem.startsWith(u8, item, "-D")) item[2..] else item;
        if (d.len > 0) out.append(b.allocator, b.dupe(d)) catch {};
    }
}

fn classifyCMakeLibs(b: *std.Build, val: []const u8, ll: *StrList, lf: *StrList, fw: *StrList) void {
    var it = std.mem.tokenizeScalar(u8, val, ';');
    while (it.next()) |item| {
        const t = std.mem.trim(u8, item, " \t\r");
        if (t.len == 0) continue;
        // Old-style keyword entries in <pkg>_LIBRARIES.
        if (std.mem.eql(u8, t, "optimized") or std.mem.eql(u8, t, "debug") or std.mem.eql(u8, t, "general")) continue;
        // An unresolved imported-target name; needs .cmake_target to read.
        if (std.mem.indexOf(u8, t, "::") != null) continue;
        if (t[0] == '/' and hasLibExt(t)) {
            lf.append(b.allocator, b.dupe(t)) catch {};
        } else if (std.mem.startsWith(u8, t, "-l")) {
            ll.append(b.allocator, b.dupe(t[2..])) catch {};
        } else if (std.mem.startsWith(u8, t, "-framework")) {
            const rest = std.mem.trim(u8, t["-framework".len..], " \t");
            if (rest.len > 0) fw.append(b.allocator, b.dupe(rest)) catch {};
        } else if (t[0] != '-') {
            // A bare library name.
            ll.append(b.allocator, b.dupe(t)) catch {};
        }
    }
}
