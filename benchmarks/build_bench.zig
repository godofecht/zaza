//! Build-time benchmark harness for Zaza.
//!
//! Everything reported here is measured. The harness generates a synthetic C++
//! project, builds it through each available lane, and times the real child
//! processes with a monotonic clock. Nothing is modelled, estimated or
//! extrapolated. If a lane is unavailable the harness says so and reports the
//! lanes that ran.
//!
//! Lanes:
//!   zaza        `zig build` driving build_lib/cpp_example.zig, Zig's clang
//!   cmake-sys   `cmake` + Ninja, system c++
//!   cmake-zigcc `cmake` + Ninja, `zig c++` as CMAKE_CXX_COMPILER
//!
//! The cmake-zigcc lane exists so that at least one comparison holds the
//! compiler fixed. Comparing zaza against cmake-sys also compares two different
//! C++ compilers and two different standard libraries.

const std = @import("std");
const builtin = @import("builtin");

const max_samples = 64;

// ---------------------------------------------------------------------------
// Output. Written straight to the stdout handle so the same spelling works on
// 0.14.1 and 0.15.2, whose formatted-writer APIs differ.
// ---------------------------------------------------------------------------

var line_buf: [16 * 1024]u8 = undefined;

fn stdoutFile() std.fs.File {
    if (comptime @hasDecl(std.fs.File, "stdout")) {
        return std.fs.File.stdout();
    } else {
        return std.io.getStdOut();
    }
}

fn p(comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(&line_buf, fmt, args) catch return;
    stdoutFile().writeAll(s) catch {};
}

// ---------------------------------------------------------------------------
// Child processes
// ---------------------------------------------------------------------------

const Outcome = struct {
    ok: bool,
    ns: u64,
};

fn childOk(term: std.process.Child.Term) bool {
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

/// Run argv in cwd and return the wall-clock nanoseconds it took. Output is
/// captured (and discarded on success) so build chatter does not interleave
/// with the report. The capture overhead is identical for every lane.
fn timedRun(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    cwd: []const u8,
    env: *const std.process.EnvMap,
) Outcome {
    var timer = std.time.Timer.start() catch return .{ .ok = false, .ns = 0 };
    const res = std.process.Child.run(.{
        .allocator = gpa,
        .argv = argv,
        .cwd = cwd,
        .env_map = env,
        .max_output_bytes = 32 * 1024 * 1024,
    }) catch |err| {
        p("  ! spawn failed: {s}: {s}\n", .{ argv[0], @errorName(err) });
        return .{ .ok = false, .ns = 0 };
    };
    const ns = timer.read();
    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);

    if (!childOk(res.term)) {
        p("  ! command failed: ", .{});
        for (argv) |a| p("{s} ", .{a});
        p("\n", .{});
        const tail = if (res.stderr.len > 2000) res.stderr[res.stderr.len - 2000 ..] else res.stderr;
        p("{s}\n", .{tail});
        return .{ .ok = false, .ns = ns };
    }
    return .{ .ok = true, .ns = ns };
}

/// Capture the first line of a command's stdout. Used for version probing.
fn firstLine(gpa: std.mem.Allocator, argv: []const []const u8) ?[]u8 {
    const res = std.process.Child.run(.{
        .allocator = gpa,
        .argv = argv,
        .max_output_bytes = 1 << 20,
    }) catch return null;
    defer gpa.free(res.stderr);
    if (!childOk(res.term)) {
        gpa.free(res.stdout);
        return null;
    }
    const trimmed = std.mem.trim(u8, res.stdout, " \t\r\n");
    var it = std.mem.splitScalar(u8, trimmed, '\n');
    const line = it.next() orelse "";
    const owned = gpa.dupe(u8, std.mem.trim(u8, line, " \t\r")) catch null;
    gpa.free(res.stdout);
    return owned;
}

/// std.process.EnvMap has no clone, so copy entry by entry.
fn cloneEnv(gpa: std.mem.Allocator, src: *const std.process.EnvMap) !*std.process.EnvMap {
    const out = try gpa.create(std.process.EnvMap);
    out.* = std.process.EnvMap.init(gpa);
    var it = src.iterator();
    while (it.next()) |kv| try out.put(kv.key_ptr.*, kv.value_ptr.*);
    return out;
}

fn haveTool(gpa: std.mem.Allocator, name: []const u8) bool {
    const res = std.process.Child.run(.{
        .allocator = gpa,
        .argv = &.{ "/usr/bin/env", "which", name },
        .max_output_bytes = 1 << 16,
    }) catch return false;
    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);
    return childOk(res.term);
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

const Stats = struct {
    n: usize,
    min_ns: u64,
    med_ns: u64,
    max_ns: u64,

    fn spreadPct(self: Stats) f64 {
        if (self.min_ns == 0) return 0;
        const lo: f64 = @floatFromInt(self.min_ns);
        const hi: f64 = @floatFromInt(self.max_ns);
        return (hi / lo - 1.0) * 100.0;
    }

    fn noisy(self: Stats) bool {
        return self.spreadPct() > 25.0;
    }
};

fn summarise(samples: []u64) ?Stats {
    if (samples.len == 0) return null;
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    const mid = samples.len / 2;
    const med = if (samples.len % 2 == 1)
        samples[mid]
    else
        (samples[mid - 1] + samples[mid]) / 2;
    return .{
        .n = samples.len,
        .min_ns = samples[0],
        .med_ns = med,
        .max_ns = samples[samples.len - 1],
    };
}

fn ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

// ---------------------------------------------------------------------------
// Phases and lanes
// ---------------------------------------------------------------------------

const Phase = enum {
    configure,
    clean_build,
    noop_rebuild,
    incremental_rebuild,

    fn label(self: Phase) []const u8 {
        return switch (self) {
            .configure => "configure",
            .clean_build => "clean build",
            .noop_rebuild => "no-op rebuild",
            .incremental_rebuild => "incremental (1 TU)",
        };
    }
};

const phase_count = @typeInfo(Phase).@"enum".fields.len;

const Lane = struct {
    id: []const u8,
    label: []const u8,
    caveat: []const u8,
    /// Absolute path to the lane's project directory.
    dir: []const u8,
    /// Directories under `dir` removed before a clean build.
    wipe: []const []const u8,
    configure_argv: []const []const u8,
    build_argv: []const []const u8,
    env: *std.process.EnvMap,

    samples: [phase_count][max_samples]u64 = undefined,
    sample_count: [phase_count]usize = .{0} ** phase_count,
    warmup: [phase_count]u64 = .{0} ** phase_count,
    failed: bool = false,

    fn record(self: *Lane, phase: Phase, ns: u64) void {
        const i = @intFromEnum(phase);
        if (self.sample_count[i] >= max_samples) return;
        self.samples[i][self.sample_count[i]] = ns;
        self.sample_count[i] += 1;
    }

    fn stats(self: *Lane, phase: Phase) ?Stats {
        const i = @intFromEnum(phase);
        return summarise(self.samples[i][0..self.sample_count[i]]);
    }
};

// ---------------------------------------------------------------------------
// Workload generation
//
// Every lane compiles byte-identical sources. `seed` is the only thing that
// changes for the incremental step, and it changes the body of one translation
// unit. It has to be a real content change: Zig's cache keys on file contents,
// Ninja keys on mtime, so a bare `touch` would rebuild under one and not the
// other and the comparison would be meaningless.
// ---------------------------------------------------------------------------

fn writeFile(dir: []const u8, rel: []const u8, bytes: []const u8) !void {
    var d = try std.fs.cwd().openDir(dir, .{});
    defer d.close();
    if (std.fs.path.dirname(rel)) |sub| try d.makePath(sub);
    var f = try d.createFile(rel, .{ .truncate = true });
    defer f.close();
    try f.writeAll(bytes);
}

fn headerText(gpa: std.mem.Allocator, units: usize) ![]u8 {
    const text = try std.fmt.allocPrint(gpa,
        \\#pragma once
        \\#include <algorithm>
        \\#include <map>
        \\#include <memory>
        \\#include <string>
        \\#include <vector>
        \\
        \\namespace bench {{
        \\
        \\template <typename T>
        \\struct Bag {{
        \\    std::vector<T> items;
        \\    std::map<std::string, T> index;
        \\    void add(const std::string &k, T v) {{
        \\        items.push_back(v);
        \\        index[k] = v;
        \\    }}
        \\    T fold() const {{
        \\        T acc{{}};
        \\        for (const auto &kv : index) acc += kv.second;
        \\        std::vector<T> sorted = items;
        \\        std::sort(sorted.begin(), sorted.end());
        \\        for (const auto &v : sorted) acc += v;
        \\        return acc;
        \\    }}
        \\}};
        \\
        \\}} // namespace bench
        \\
    , .{});
    defer gpa.free(text);

    // Declare one entry point per translation unit.
    var decls = try gpa.alloc(u8, 0);
    defer gpa.free(decls);
    for (0..units) |i| {
        const line = try std.fmt.allocPrint(gpa, "long bench_unit_{d}(long x);\n", .{i});
        defer gpa.free(line);
        const joined = try std.mem.concat(gpa, u8, &.{ decls, line });
        gpa.free(decls);
        decls = joined;
    }
    return std.mem.concat(gpa, u8, &.{ text, decls });
}

fn unitText(gpa: std.mem.Allocator, index: usize, seed: usize) ![]u8 {
    return std.fmt.allocPrint(gpa,
        \\#include "bench_common.hpp"
        \\
        \\long bench_unit_{d}(long x) {{
        \\    bench::Bag<long> ints;
        \\    bench::Bag<double> reals;
        \\    for (long i = 0; i < 24; ++i) {{
        \\        ints.add(std::to_string(i) + "-{d}", i * x + {d});
        \\        reals.add(std::to_string(i), static_cast<double>(i) * 0.5);
        \\    }}
        \\    std::unique_ptr<std::vector<std::string>> names(new std::vector<std::string>());
        \\    for (const auto &kv : ints.index) names->push_back(kv.first);
        \\    std::sort(names->begin(), names->end());
        \\    long acc = ints.fold() + static_cast<long>(reals.fold());
        \\    for (const auto &n : *names) acc += static_cast<long>(n.size());
        \\    return acc;
        \\}}
        \\
    , .{ index, index, seed });
}

fn mainText(gpa: std.mem.Allocator, units: usize) ![]u8 {
    var body = try gpa.alloc(u8, 0);
    defer gpa.free(body);
    for (0..units) |i| {
        const line = try std.fmt.allocPrint(gpa, "    total += bench_unit_{d}({d});\n", .{ i, i + 1 });
        defer gpa.free(line);
        const joined = try std.mem.concat(gpa, u8, &.{ body, line });
        gpa.free(body);
        body = joined;
    }
    const head =
        \\#include "bench_common.hpp"
        \\#include <cstdio>
        \\
        \\int main() {
        \\    long total = 0;
        \\
    ;
    const tail =
        \\    std::printf("%ld\n", total);
        \\    return 0;
        \\}
        \\
    ;
    return std.mem.concat(gpa, u8, &.{ head, body, tail });
}

fn zazaBuildZig(gpa: std.mem.Allocator, units: usize) ![]u8 {
    var srcs = try gpa.alloc(u8, 0);
    defer gpa.free(srcs);
    for (0..units) |i| {
        const line = try std.fmt.allocPrint(gpa, "        \"src/unit_{d}.cpp\",\n", .{i});
        defer gpa.free(line);
        const joined = try std.mem.concat(gpa, u8, &.{ srcs, line });
        gpa.free(srcs);
        srcs = joined;
    }
    const head =
        \\// Generated by benchmarks/build_bench.zig. Declares the synthetic
        \\// workload as a Zaza C++ target.
        \\const std = @import("std");
        \\const cpp = @import("build_lib/cpp_example.zig");
        \\
        \\pub var example = cpp.CppExample{
        \\    .name = "bench_app",
        \\    .description = "synthetic benchmark workload",
        \\    .source_files = &.{
        \\        "src/main.cpp",
        \\
    ;
    const tail =
        \\    },
        \\    .include_dirs = &.{"include"},
        \\    .cpp_flags = &.{},
        \\    .deps = &.{},
        \\    .configs = &.{.{ .mode = .Debug }},
        \\    .deps_build_system = .Zig,
        \\    .main_build_system = .Zig,
        \\    .cpp_std = "17",
        \\};
        \\
        \\pub fn build(b: *std.Build) !void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const exe = try example.buildWithTarget(b, target);
        \\    b.installArtifact(exe);
        \\}
        \\
    ;
    return std.mem.concat(gpa, u8, &.{ head, srcs, tail });
}

fn cmakeLists(gpa: std.mem.Allocator, units: usize) ![]u8 {
    var srcs = try gpa.alloc(u8, 0);
    defer gpa.free(srcs);
    for (0..units) |i| {
        const line = try std.fmt.allocPrint(gpa, "    src/unit_{d}.cpp\n", .{i});
        defer gpa.free(line);
        const joined = try std.mem.concat(gpa, u8, &.{ srcs, line });
        gpa.free(srcs);
        srcs = joined;
    }
    const head =
        \\# Generated by benchmarks/build_bench.zig.
        \\cmake_minimum_required(VERSION 3.20)
        \\project(bench_app CXX)
        \\set(CMAKE_CXX_STANDARD 17)
        \\set(CMAKE_CXX_STANDARD_REQUIRED ON)
        \\add_executable(bench_app
        \\    src/main.cpp
        \\
    ;
    const tail =
        \\)
        \\target_include_directories(bench_app PRIVATE include)
        \\
    ;
    return std.mem.concat(gpa, u8, &.{ head, srcs, tail });
}

/// Write the shared sources into `dir`. Called once at setup and again before
/// every repetition so each repetition starts from identical bytes.
fn writeSources(gpa: std.mem.Allocator, dir: []const u8, units: usize, seed: usize) !void {
    const hdr = try headerText(gpa, units);
    defer gpa.free(hdr);
    try writeFile(dir, "include/bench_common.hpp", hdr);

    for (0..units) |i| {
        const body = try unitText(gpa, i, if (i == 0) seed else 1);
        defer gpa.free(body);
        const name = try std.fmt.allocPrint(gpa, "src/unit_{d}.cpp", .{i});
        defer gpa.free(name);
        try writeFile(dir, name, body);
    }

    const m = try mainText(gpa, units);
    defer gpa.free(m);
    try writeFile(dir, "src/main.cpp", m);
}

/// Rewrite unit_0.cpp with a different constant. A genuine content change, so
/// both a content-hashing cache and an mtime-based one see work to do.
fn touchOneUnit(gpa: std.mem.Allocator, dir: []const u8, seed: usize) !void {
    const body = try unitText(gpa, 0, seed);
    defer gpa.free(body);
    try writeFile(dir, "src/unit_0.cpp", body);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const Options = struct {
    zig_exe: []const u8 = "zig",
    repo_root: []const u8 = "..",
    workspace: []const u8 = "",
    reps: usize = 5,
    warmups: usize = 1,
    units: usize = 16,
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const gpa = arena_state.allocator();

    var opt = Options{};
    const args = try std.process.argsAlloc(gpa);
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--zig") and i + 1 < args.len) {
            i += 1;
            opt.zig_exe = args[i];
        } else if (std.mem.eql(u8, a, "--repo-root") and i + 1 < args.len) {
            i += 1;
            opt.repo_root = args[i];
        } else if (std.mem.eql(u8, a, "--workspace") and i + 1 < args.len) {
            i += 1;
            opt.workspace = args[i];
        } else if (std.mem.eql(u8, a, "--reps") and i + 1 < args.len) {
            i += 1;
            opt.reps = std.fmt.parseInt(usize, args[i], 10) catch opt.reps;
        } else if (std.mem.eql(u8, a, "--warmups") and i + 1 < args.len) {
            i += 1;
            opt.warmups = std.fmt.parseInt(usize, args[i], 10) catch opt.warmups;
        } else if (std.mem.eql(u8, a, "--units") and i + 1 < args.len) {
            i += 1;
            opt.units = std.fmt.parseInt(usize, args[i], 10) catch opt.units;
        } else if (std.mem.eql(u8, a, "--help")) {
            p(
                \\usage: build_bench [options]
                \\  --zig PATH         zig binary under test
                \\  --repo-root PATH   zaza checkout to take build_lib from
                \\  --workspace PATH   scratch directory for generated projects
                \\  --reps N           measured repetitions per lane (default 5)
                \\  --warmups N        discarded warm-up repetitions (default 1)
                \\  --units N          translation units in the workload (default 16)
                \\
            , .{});
            return;
        }
    }
    if (opt.reps < 1) opt.reps = 1;
    if (opt.reps > max_samples) opt.reps = max_samples;

    const repo_root = try std.fs.cwd().realpathAlloc(gpa, opt.repo_root);
    const ws = if (opt.workspace.len > 0)
        opt.workspace
    else
        try std.fs.path.join(gpa, &.{ repo_root, "benchmarks", ".workspace" });

    // ----- workspace ------------------------------------------------------
    std.fs.cwd().deleteTree(ws) catch {};
    try std.fs.cwd().makePath(ws);
    const ws_abs = try std.fs.cwd().realpathAlloc(gpa, ws);

    const zig_global_cache = try std.fs.path.join(gpa, &.{ ws_abs, ".zig-global-cache" });
    try std.fs.cwd().makePath(zig_global_cache);

    var base_env = try std.process.getEnvMap(gpa);
    // Keep the harness deterministic against the caller's environment.
    base_env.remove("ZIG_LOCAL_CACHE_DIR");
    base_env.remove("ZIG_GLOBAL_CACHE_DIR");

    // ----- tool discovery -------------------------------------------------
    const have_cmake = haveTool(gpa, "cmake");
    const have_ninja = haveTool(gpa, "ninja");
    const have_cxx = haveTool(gpa, "c++");

    var lanes = try gpa.alloc(Lane, 3);
    var lane_n: usize = 0;

    // zaza lane -------------------------------------------------------------
    {
        const dir = try std.fs.path.join(gpa, &.{ ws_abs, "zaza_proj" });
        try std.fs.cwd().makePath(dir);
        try writeSources(gpa, dir, opt.units, 1);

        // build_lib is copied in so the generated project is a self-contained
        // Zig package. cpp_example.zig imports only zaza_cmd.zig.
        var lib_dir = try std.fs.cwd().openDir(dir, .{});
        try lib_dir.makePath("build_lib");
        lib_dir.close();
        inline for (.{ "cpp_example.zig", "zaza_cmd.zig" }) |f| {
            const src = try std.fs.path.join(gpa, &.{ repo_root, "build_lib", f });
            const dst = try std.fs.path.join(gpa, &.{ dir, "build_lib", f });
            try std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{});
        }

        const bz = try zazaBuildZig(gpa, opt.units);
        try writeFile(dir, "build.zig", bz);

        const env = try cloneEnv(gpa, &base_env);
        // Local cache lives in the project and is wiped for a clean build.
        // The global cache is shared and warmed once: wiping it would force a
        // rebuild of libc++ and compiler-rt, which no user does between
        // ordinary clean builds.
        try env.put("ZIG_GLOBAL_CACHE_DIR", zig_global_cache);
        try env.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(gpa, &.{ dir, ".zig-cache" }));

        lanes[lane_n] = .{
            .id = "zaza",
            .label = "zaza (zig build)",
            .caveat = "Zig's bundled clang and libc++.",
            .dir = dir,
            .wipe = try gpa.dupe([]const u8, &.{ ".zig-cache", "zig-out" }),
            // `zig build --help` compiles and runs the build script and
            // enumerates the graph without compiling C++. It is the closest
            // analogue to a CMake configure step.
            .configure_argv = try gpa.dupe([]const u8, &.{ opt.zig_exe, "build", "--help" }),
            .build_argv = try gpa.dupe([]const u8, &.{ opt.zig_exe, "build" }),
            .env = env,
        };
        lane_n += 1;
    }

    // cmake lanes -----------------------------------------------------------
    if (have_cmake and have_ninja) {
        const zigcxx = try std.fs.path.join(gpa, &.{ ws_abs, "zigcxx" });
        {
            const sh = try std.fmt.allocPrint(gpa, "#!/bin/sh\nexec \"{s}\" c++ \"$@\"\n", .{opt.zig_exe});
            var f = try std.fs.cwd().createFile(zigcxx, .{ .truncate = true, .mode = 0o755 });
            defer f.close();
            try f.writeAll(sh);
        }

        const Variant = struct {
            id: []const u8,
            label: []const u8,
            caveat: []const u8,
            dirname: []const u8,
            compiler: ?[]const u8,
            enabled: bool,
        };
        const variants = [_]Variant{
            .{
                .id = "cmake-sys",
                .label = "cmake + ninja (system c++)",
                .caveat = "different compiler and stdlib from the zaza lane.",
                .dirname = "cmake_sys_proj",
                .compiler = null,
                .enabled = have_cxx,
            },
            .{
                .id = "cmake-zigcc",
                .label = "cmake + ninja (zig c++)",
                .caveat = "same compiler as the zaza lane.",
                .dirname = "cmake_zigcc_proj",
                .compiler = zigcxx,
                .enabled = true,
            },
        };

        for (variants) |v| {
            if (!v.enabled) continue;
            const dir = try std.fs.path.join(gpa, &.{ ws_abs, v.dirname });
            try std.fs.cwd().makePath(dir);
            try writeSources(gpa, dir, opt.units, 1);
            const cl = try cmakeLists(gpa, opt.units);
            try writeFile(dir, "CMakeLists.txt", cl);

            const env = try cloneEnv(gpa, &base_env);

            var configure: []const []const u8 = undefined;
            if (v.compiler) |cc| {
                configure = try gpa.dupe([]const u8, &.{
                    "cmake", "-S", ".", "-B", "build", "-G", "Ninja",
                    "-DCMAKE_BUILD_TYPE=Debug",
                    try std.fmt.allocPrint(gpa, "-DCMAKE_CXX_COMPILER={s}", .{cc}),
                });
            } else {
                configure = try gpa.dupe([]const u8, &.{
                    "cmake", "-S", ".", "-B", "build", "-G", "Ninja",
                    "-DCMAKE_BUILD_TYPE=Debug",
                });
            }

            lanes[lane_n] = .{
                .id = v.id,
                .label = v.label,
                .caveat = v.caveat,
                .dir = dir,
                .wipe = try gpa.dupe([]const u8, &.{"build"}),
                .configure_argv = configure,
                .build_argv = try gpa.dupe([]const u8, &.{ "cmake", "--build", "build" }),
                .env = env,
            };
            lane_n += 1;
        }
    }
    lanes = lanes[0..lane_n];

    // ----- header ----------------------------------------------------------
    p("Zaza build benchmark\n", .{});
    p("====================\n\n", .{});
    p("Every number below is a wall-clock measurement of a child process on\n", .{});
    p("this machine, taken during this run. Nothing is modelled.\n\n", .{});

    p("machine\n", .{});
    if (firstLine(gpa, &.{ "uname", "-srm" })) |v| p("  uname            {s}\n", .{v});
    if (builtin.os.tag == .macos) {
        if (firstLine(gpa, &.{ "sysctl", "-n", "machdep.cpu.brand_string" })) |v| p("  cpu              {s}\n", .{v});
        if (firstLine(gpa, &.{ "sw_vers", "-productVersion" })) |v| p("  macos            {s}\n", .{v});
    }
    if (firstLine(gpa, &.{ "/usr/bin/env", "getconf", "_NPROCESSORS_ONLN" })) |v| p("  logical cpus     {s}\n", .{v});
    p("\ntoolchain\n", .{});
    if (firstLine(gpa, &.{ opt.zig_exe, "version" })) |v| p("  zig              {s}  ({s})\n", .{ v, opt.zig_exe });
    if (firstLine(gpa, &.{ "cmake", "--version" })) |v| p("  cmake            {s}\n", .{v});
    if (firstLine(gpa, &.{ "ninja", "--version" })) |v| p("  ninja            {s}\n", .{v});
    if (firstLine(gpa, &.{ "c++", "--version" })) |v| p("  system c++       {s}\n", .{v});

    p("\nworkload\n", .{});
    p("  {d} C++17 translation units plus main.cpp, one shared header,\n", .{opt.units});
    p("  linked into one executable. Byte-identical sources in every lane.\n", .{});
    p("  workspace: {s}\n", .{ws_abs});
    p("\nprotocol\n", .{});
    p("  {d} warm-up repetition(s), discarded and reported separately, then\n", .{opt.warmups});
    p("  {d} measured repetition(s). Lanes are interleaved within a repetition\n", .{opt.reps});
    p("  so they see the same machine state. Each repetition does:\n", .{});
    p("    wipe build outputs -> configure -> clean build -> no-op rebuild ->\n", .{});
    p("    change one translation unit -> incremental rebuild.\n", .{});
    p("  The incremental change edits an integer in unit_0.cpp. It has to be a\n", .{});
    p("  real content change, because Zig's cache keys on content and Ninja's\n", .{});
    p("  on mtime.\n", .{});

    p("\nlanes\n", .{});
    for (lanes) |l| p("  {s:<28} {s}\n", .{ l.label, l.caveat });
    if (lane_n == 1) {
        p("\n  No CMake lane was available (cmake and ninja must both be on PATH),\n", .{});
        p("  so no comparison is reported. The zaza numbers stand alone.\n", .{});
    }

    // ----- warm the shared zig global cache --------------------------------
    p("\nwarming the shared Zig global cache (not timed)\n", .{});
    {
        const warm = timedRun(gpa, lanes[0].build_argv, lanes[0].dir, lanes[0].env);
        if (!warm.ok) {
            p("zaza lane failed to build. Aborting.\n", .{});
            return error.LaneFailed;
        }
    }

    // ----- run -------------------------------------------------------------
    const total_reps = opt.warmups + opt.reps;
    var rep: usize = 0;
    while (rep < total_reps) : (rep += 1) {
        const measured = rep >= opt.warmups;
        if (measured) {
            p("\nrepetition {d}/{d}\n", .{ rep - opt.warmups + 1, opt.reps });
        } else {
            p("\nwarm-up repetition {d}/{d} (discarded)\n", .{ rep + 1, opt.warmups });
        }

        for (lanes) |*lane| {
            if (lane.failed) continue;

            // Reset sources to the baseline seed.
            try writeSources(gpa, lane.dir, opt.units, 1);

            // Wipe build outputs.
            for (lane.wipe) |w| {
                const path = try std.fs.path.join(gpa, &.{ lane.dir, w });
                std.fs.cwd().deleteTree(path) catch {};
            }

            const cfg = timedRun(gpa, lane.configure_argv, lane.dir, lane.env);
            const clean = if (cfg.ok) timedRun(gpa, lane.build_argv, lane.dir, lane.env) else Outcome{ .ok = false, .ns = 0 };
            const noop = if (clean.ok) timedRun(gpa, lane.build_argv, lane.dir, lane.env) else Outcome{ .ok = false, .ns = 0 };

            var incr = Outcome{ .ok = false, .ns = 0 };
            if (noop.ok) {
                try touchOneUnit(gpa, lane.dir, 2 + rep);
                incr = timedRun(gpa, lane.build_argv, lane.dir, lane.env);
            }

            if (!(cfg.ok and clean.ok and noop.ok and incr.ok)) {
                p("  {s}: lane failed, dropping it from the results\n", .{lane.id});
                lane.failed = true;
                continue;
            }

            if (measured) {
                lane.record(.configure, cfg.ns);
                lane.record(.clean_build, clean.ns);
                lane.record(.noop_rebuild, noop.ns);
                lane.record(.incremental_rebuild, incr.ns);
            } else {
                lane.warmup[@intFromEnum(Phase.configure)] = cfg.ns;
                lane.warmup[@intFromEnum(Phase.clean_build)] = clean.ns;
                lane.warmup[@intFromEnum(Phase.noop_rebuild)] = noop.ns;
                lane.warmup[@intFromEnum(Phase.incremental_rebuild)] = incr.ns;
            }

            p("  {s:<28} cfg {d:>8.1} ms  clean {d:>8.1} ms  no-op {d:>8.1} ms  incr {d:>8.1} ms\n", .{
                lane.label, ms(cfg.ns), ms(clean.ns), ms(noop.ns), ms(incr.ns),
            });
        }
    }

    // ----- report ----------------------------------------------------------
    p("\n\nresults\n", .{});
    p("-------\n", .{});
    p("Wall clock, milliseconds. n is the number of measured repetitions.\n", .{});
    p("spread is (max/min - 1); anything above 25% is flagged noisy and should\n", .{});
    p("not be read as a precise figure.\n\n", .{});

    p("{s:<28} {s:<20} {s:>3} {s:>10} {s:>10} {s:>10} {s:>8}\n", .{
        "lane", "phase", "n", "min", "median", "max", "spread",
    });
    p("{s}\n", .{"-" ** 94});

    for (lanes) |*lane| {
        if (lane.failed) continue;
        inline for (@typeInfo(Phase).@"enum".fields) |f| {
            const phase: Phase = @enumFromInt(f.value);
            if (lane.stats(phase)) |s| {
                p("{s:<28} {s:<20} {d:>3} {d:>10.1} {d:>10.1} {d:>10.1} {d:>7.0}%{s}\n", .{
                    lane.label,
                    phase.label(),
                    s.n,
                    ms(s.min_ns),
                    ms(s.med_ns),
                    ms(s.max_ns),
                    s.spreadPct(),
                    if (s.noisy()) "  NOISY" else "",
                });
            }
        }
        p("\n", .{});
    }

    if (opt.warmups > 0) {
        p("discarded warm-up repetition (cold caches, reported for reference only)\n", .{});
        for (lanes) |*lane| {
            if (lane.failed) continue;
            p("  {s:<28} cfg {d:>8.1} ms  clean {d:>8.1} ms  no-op {d:>8.1} ms  incr {d:>8.1} ms\n", .{
                lane.label,
                ms(lane.warmup[0]),
                ms(lane.warmup[1]),
                ms(lane.warmup[2]),
                ms(lane.warmup[3]),
            });
        }
        p("\n", .{});
    }

    // ----- comparison ------------------------------------------------------
    var live: usize = 0;
    for (lanes) |*l| {
        if (!l.failed) live += 1;
    }

    if (live < 2) {
        p("comparison\n", .{});
        p("  Only one lane produced measurements, so no comparison is reported.\n", .{});
        p("  Zaza is measured alone above.\n", .{});
    } else {
        p("comparison (ratio of medians, both lanes measured in this same run\n", .{});
        p("on this same machine; >1.00 means zaza took longer)\n\n", .{});
        p("{s:<20} {s:>16} {s:>16} {s:>16} {s:>16}\n", .{
            "vs", "configure", "clean build", "no-op rebuild", "incremental",
        });
        p("{s}\n", .{"-" ** 88});
        const base = &lanes[0];
        for (lanes[1..]) |*other| {
            if (other.failed or base.failed) continue;
            p("{s:<20}", .{other.id});
            inline for (@typeInfo(Phase).@"enum".fields) |f| {
                const phase: Phase = @enumFromInt(f.value);
                const a = base.stats(phase);
                const b = other.stats(phase);
                if (a != null and b != null and b.?.med_ns != 0) {
                    const r = @as(f64, @floatFromInt(a.?.med_ns)) / @as(f64, @floatFromInt(b.?.med_ns));
                    const flag = if (a.?.noisy() or b.?.noisy()) "?" else " ";
                    p("{d:>15.2}{s}", .{ r, flag });
                } else {
                    p("{s:>16}", .{"n/a"});
                }
            }
            p("\n", .{});
        }
        p("\n  '?' marks a ratio where at least one side was noisy.\n", .{});
        p("\n  What these ratios do and do not mean:\n", .{});
        p("  - cmake-zigcc holds the compiler fixed, so that column is the\n", .{});
        p("    closest thing here to a build-system comparison.\n", .{});
        p("  - cmake-sys uses a different compiler and standard library, so the\n", .{});
        p("    clean-build column there measures two compilers as much as two\n", .{});
        p("    build systems. Read it with that in mind.\n", .{});
        p("  - 'configure' compares a CMake configure against `zig build --help`,\n", .{});
        p("    which compiles and runs the build script. They are analogues, not\n", .{});
        p("    the same operation.\n", .{});
        p("  - The zaza clean build also installs into zig-out. The CMake lanes\n", .{});
        p("    do not install.\n", .{});
    }

    p("\nnot measured here\n", .{});
    p("  - Dependency fetching. Zaza clones dependencies with git and CMake\n", .{});
    p("    projects use FetchContent or a system package manager. Those do\n", .{});
    p("    different work over a network, so any timing would be a network\n", .{});
    p("    measurement, not a build-system one.\n", .{});
    p("  - Memory use. No memory figure is collected, so none is reported.\n", .{});
    p("  - Large-project scaling. Only the workload size above was run. Change\n", .{});
    p("    it with --units and rerun if you want another point.\n", .{});
    p("  - The cmake_shim, cmake_combo and cmake_net examples. They fetch from\n", .{});
    p("    the network and drive CMake as a subordinate step, so they are not a\n", .{});
    p("    like-for-like race against anything.\n", .{});
}
