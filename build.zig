const std = @import("std");
const builtin = @import("builtin");
const json_example = @import("examples/json/build.zig");
const juce_example = @import("examples/juce/build.zig");
const cmake_shim_example = @import("examples/cmake_shim/build.zig");
const hello_vex_example = @import("examples/hello_vex/build.zig");
const cmake_combo_example = @import("examples/cmake_combo/build.zig");
const cmake_net_example = @import("examples/cmake_net/build.zig");
const proof_library_example = @import("examples/proof_library/build.zig");
const generated_code_example = @import("examples/generated_code/build.zig");
const package_producer_example = @import("examples/package_producer/build.zig");
const mixed_stack_example = @import("examples/mixed_stack/build.zig");
const interface_object_graph_example = @import("examples/interface_object_graph/build.zig");
const vex_cmd = @import("build_lib/vex_cmd.zig");
const cpp = @import("build_lib/cpp_example.zig");
const presets = @import("build_lib/presets.zig");

pub fn build(b: *std.Build) !void {
    // Preflight: ensure a writable cache dir or guide the user.
    if (!cacheWritable(b)) {
        @panic(
            "Zig cache is not writable. Set ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR, "
            ++ "or enable direnv (see .envrc) for a portable setup."
        );
    }

    const system_cmds = b.option(bool, "system-cmds", "Enable git/cmake steps in build") orelse (envBool(b, "VEX_SYSTEM_CMDS") orelse false);
    const verbose = b.option(bool, "verbose", "Print build status messages") orelse true;
    const target = selectTarget(b);
    const optimize = b.standardOptimizeOption(.{});

    // Auto-fetch registry deps into build.zig.zon (can disable with VEX_REGISTRY=0)
    try ensureRegistryDeps(b);

    // Apply preset configs to examples (optional)
    if (envString(b, "VEX_PRESET")) |preset| {
        defer b.allocator.free(preset);
        applyPresetToExample(&cmake_combo_example.example, preset);
        applyPresetToExample(&cmake_net_example.example, preset);
        applyPresetToExample(&cmake_shim_example.example, preset);
    }

    if (exampleEnabled(b, "json")) {
        json_example.example.enable_system_commands = system_cmds;
        try json_example.buildWithTarget(b, target);
    }

    if (exampleEnabled(b, "juce")) {
        const juce_step = b.step("juce", "Build the JUCE example");
        // JUCE build uses CMake/system commands.
        try juce_example.buildWithTarget(b, target);
        juce_step.dependOn(b.getInstallStep());
    }

    const hello_step = b.step("hello-vex", "Build hello_vex (Zig + C++ via Vex)");
    const hello_artifacts = try hello_vex_example.addArtifacts(b, target, optimize);
    hello_step.dependOn(&b.addInstallArtifact(hello_artifacts.zig_exe, .{}).step);
    hello_step.dependOn(&b.addInstallArtifact(hello_artifacts.cpp_exe, .{}).step);

    const hello_run_zig = b.addRunArtifact(hello_artifacts.zig_exe);
    const hello_run_cpp = b.addRunArtifact(hello_artifacts.cpp_exe);
    const hello_run_step = b.step("run-hello-vex", "Run both hello_vex executables");
    hello_run_step.dependOn(&hello_run_zig.step);
    hello_run_step.dependOn(&hello_run_cpp.step);

    if (exampleEnabled(b, "proof-library")) {
        try proof_library_example.build(b, target, optimize);
    }

    if (exampleEnabled(b, "generated-code")) {
        try generated_code_example.build(b, target, optimize);
    }

    var package_producer_steps: ?package_producer_example.BuildResult = null;
    if (exampleEnabled(b, "package-producer")) {
        package_producer_steps = try package_producer_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "package-consumer")) {
        if (package_producer_steps == null) {
            package_producer_steps = try package_producer_example.addSteps(b, target, optimize);
        }

        const producer_install = b.addSystemCommand(&.{
            "env",
            "VEX_EXAMPLES=package-producer",
            "./zig",
            "build",
            "install",
        });
        producer_install.stdio = .inherit;
        producer_install.step.dependencies.append(package_producer_steps.?.build_step) catch unreachable;

        const consumer_build = b.addSystemCommand(&.{
            "./zig",
            "build",
            "--build-file",
            "examples/package_consumer/build.zig",
            "package-consumer",
            "-Dpackage-prefix=zig-out",
        });
        consumer_build.stdio = .inherit;
        consumer_build.step.dependencies.append(&producer_install.step) catch unreachable;

        const consumer_step = b.step("package-consumer", "Build the downstream package consumer example");
        consumer_step.dependOn(&consumer_build.step);

        const consumer_run = b.addSystemCommand(&.{
            "./zig",
            "build",
            "--build-file",
            "examples/package_consumer/build.zig",
            "run",
            "-Dpackage-prefix=zig-out",
        });
        consumer_run.stdio = .inherit;
        consumer_run.step.dependencies.append(&consumer_build.step) catch unreachable;

        const consumer_run_step = b.step("package-consumer-run", "Run the downstream package consumer example");
        consumer_run_step.dependOn(&consumer_run.step);
    }

    if (exampleEnabled(b, "mixed-stack")) {
        _ = mixed_stack_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "interface-object-graph")) {
        _ = interface_object_graph_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "cmake-combo")) {
        const combo_step = b.step("cmake-combo", "Build CMake combo example (fmt + spdlog)");
        // cmake-combo always enables system commands so it works out-of-the-box.
        cmake_combo_example.example.enable_system_commands = true;
        const combo_exe = try cmake_combo_example.buildWithTarget(b, target);
        combo_step.dependOn(&b.addInstallArtifact(combo_exe, .{}).step);

        const combo_run = b.addRunArtifact(combo_exe);
        const combo_run_step = b.step("cmake-combo-run", "Run the CMake combo example (fmt + spdlog)");
        const combo_banner = addBannerStep(b, "cmake-combo", "=== RUN: cmake-combo ===");
        combo_run.step.dependencies.append(combo_banner) catch unreachable;
        combo_run_step.dependOn(&combo_run.step);
    }

    if (exampleEnabled(b, "cmake-net")) {
        const net_step = b.step("cmake-net", "Build CMake networking example (curl + zlib + mbedtls)");
        cmake_net_example.example.enable_system_commands = true;
        const net_exe = try cmake_net_example.buildWithTarget(b, target);
        net_step.dependOn(&b.addInstallArtifact(net_exe, .{}).step);

        const net_run = b.addRunArtifact(net_exe);
        const net_run_step = b.step("cmake-net-run", "Run the CMake networking example (curl + zlib + mbedtls)");
        const net_banner = addBannerStep(b, "cmake-net", "=== RUN: cmake-net ===");
        net_run.step.dependencies.append(net_banner) catch unreachable;
        net_run_step.dependOn(&net_run.step);
    }
    
    var cmake_shim_step_opt: ?*std.Build.Step = null;
    var cmake_run_step: ?*std.Build.Step = null;
    var cmake_install_step: ?*std.Build.Step = null;
    if (exampleEnabled(b, "cmake-shim")) {
        const cmake_shim_step = b.step("cmake-shim", "Build the CMake shim example");
        cmake_shim_step_opt = cmake_shim_step;
        if (!system_cmds) {
            std.debug.print("[cmake-shim] skipped: system-cmds=false. Run with -Dsystem-cmds=true or VEX_SYSTEM_CMDS=1 to enable.\n", .{});
        }
        if (system_cmds) {
            cmake_shim_example.example.enable_system_commands = true;
            const cmake_check = vex_cmd.addCommandStep(b, "cmake-version", &.{"cmake", "--version"});
            cmake_shim_step.dependOn(cmake_check);
            const cmake_exe = try cmake_shim_example.buildWithTarget(b, target);
            cmake_shim_step.dependOn(&b.addInstallArtifact(cmake_exe, .{}).step);

            const cmake_run = b.addRunArtifact(cmake_exe);
            const run_step = b.step("cmake-shim-run", "Run the CMake shim example");
            run_step.dependOn(&cmake_run.step);
            cmake_run_step = run_step;

            const install_step = b.step("cmake-install", "Build and install CMake deps marked install=true");
            install_step.dependOn(cmake_shim_step);
            cmake_install_step = install_step;
        }
    }
    
    // Add clean tests that actually work
    const test_step = b.step("test", "Run all tests");
    
    const clean_tests = b.addTest(.{
        .root_source_file = b.path("build/clean_tests.zig"),
    });
    test_step.dependOn(&b.addRunArtifact(clean_tests).step);
    
    // Also add working simple tests
    const working_tests = b.addTest(.{
        .root_source_file = b.path("src/working_test.zig"),
    });
    test_step.dependOn(&b.addRunArtifact(working_tests).step);

    // Wire up tests/
    const standalone_tests: []const []const u8 = &.{
        "tests/test_string_split.zig",
        "tests/test_fetch_minimal.zig",
        "tests/test_cpp_targets.zig",
        "tests/test_dependency_ux.zig",
        "tests/test_workflows.zig",
        "tests/test_cmake_interop.zig",
        "tests/test_interop_hints.zig",
    };
    for (standalone_tests) |path| {
        const t = b.addTest(.{ .root_source_file = b.path(path) });
        if (std.mem.eql(u8, path, "tests/test_cpp_targets.zig")) {
            t.root_module.addImport("cpp_example", b.createModule(.{
                .root_source_file = b.path("build_lib/cpp_example.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_dependency_ux.zig")) {
            t.root_module.addImport("cpp_example", b.createModule(.{
                .root_source_file = b.path("build_lib/cpp_example.zig"),
            }));
            t.root_module.addImport("vex_cli", b.createModule(.{
                .root_source_file = b.path("scripts/vex.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_workflows.zig")) {
            t.root_module.addImport("presets", b.createModule(.{
                .root_source_file = b.path("build_lib/presets.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_cmake_interop.zig")) {
            t.root_module.addImport("cpp_example", b.createModule(.{
                .root_source_file = b.path("build_lib/cpp_example.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_interop_hints.zig")) {
            t.root_module.addImport("interop_hints", b.createModule(.{
                .root_source_file = b.path("build_lib/interop_hints.zig"),
            }));
        }
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
    const deps_mod = b.createModule(.{ .root_source_file = b.path("build/dependencies.zig") });
    const builder_mod = b.createModule(.{
        .root_source_file = b.path("build/builder.zig"),
        .imports = &.{.{ .name = "zigcpp", .module = b.createModule(.{ .root_source_file = b.path("build/zigcpp.zig") }) }},
    });

    const build_module_tests: []const []const u8 = &.{
        "tests/test_builder.zig",
        "tests/test_builder_only.zig",
        "tests/test_dependencies.zig",
        "tests/test_manager_init.zig",
        "tests/test_deps_simple.zig",
        "tests/test_fetch.zig",
        "tests/test_deps_only.zig",
        "tests/test_deps_import_only.zig",
    };
    for (build_module_tests) |path| {
        const t = b.addTest(.{ .root_source_file = b.path(path) });
        t.root_module.addImport("dependencies", deps_mod);
        t.root_module.addImport("builder", builder_mod);
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    if (verbose) {
        std.debug.print("\n\x1b[1;34m=== VEX BUILD ===\x1b[0m\n", .{});
        std.debug.print("[phase] start\n", .{});
        if (system_cmds) {
            std.debug.print("[config] system-cmds=true (git/cmake enabled)\n", .{});
        } else {
            std.debug.print("[config] system-cmds=false (deps must already exist)\n", .{});
        }
        std.debug.print("[test] running\n", .{});
    }
    
    const all_step = b.step("all", "Run all tests, build default artifacts, and optionally run CMake shim");
    all_step.dependOn(test_step);
    // Build the default artifacts (e.g., json_example) via the install step.
    all_step.dependOn(b.getInstallStep());
    if (system_cmds) {
        if (cmake_shim_step_opt) |step| all_step.dependOn(step);
        if (cmake_run_step) |step| all_step.dependOn(step);
        if (cmake_install_step) |step| all_step.dependOn(step);
    }
    if (verbose) {
        std.debug.print("[build] outputs in zig-out/bin (json_example_Debug, hello_vex_*)\n", .{});
        std.debug.print("[phase] done\n", .{});
    }
    b.default_step = all_step;

    // Ad-hoc C++ runner: zig build run-cpp -- path/to/file.cpp
    const run_cpp_step = b.step("run-cpp", "Compile and run a single C++ file (usage: zig build run-cpp -- path/to/file.cpp)");
    if (b.args) |args| {
        if (args.len >= 1) {
            const src = args[0];
            const extra_flags = parseExtraFlags(args);
            const out = b.pathJoin(&.{"zig-out", "bin", "run_cpp"});

            const banner = addBannerStep(b, "run-cpp", "=== RUN: cpp ===");
            const explain = addInfoStep(b, "run-cpp-info", b.fmt(
                "src: {s}\\nout: {s}\\nflags: {s}",
                .{ src, out, joinArgs(b, extra_flags) },
            ));

            const compile = b.addSystemCommand(buildCompileArgs(b, src, out, extra_flags));
            compile.stdio = .inherit;

            const run = b.addSystemCommand(&.{out});
            run.stdio = .inherit;

            explain.dependencies.append(banner) catch unreachable;
            compile.step.dependencies.append(explain) catch unreachable;
            run.step.dependencies.append(&compile.step) catch unreachable;
            run_cpp_step.dependOn(&run.step);
        }
    }

    const run_zig_step = b.step("run-zig", "Compile and run a single Zig file (usage: zig build run-zig -- path/to/file.zig)");
    if (b.args) |args| {
        if (args.len >= 1) {
            const src = args[0];
            const out = b.pathJoin(&.{"zig-out", "bin", "run_zig"});

            const build_cmd = b.addSystemCommand(&.{"./zig", "build-exe"});
            build_cmd.addArg(src);
            build_cmd.addArg(b.fmt("-femit-bin={s}", .{out}));
            build_cmd.stdio = .inherit;
            const run = b.addSystemCommand(&.{out});
            run.stdio = .inherit;
            run.step.dependencies.append(&build_cmd.step) catch unreachable;
            run_zig_step.dependOn(&run.step);
        }
    }

    // Registry fetch: zig build vex-fetch -- <name>
    const fetch_step = b.step("vex-fetch", "Fetch a dependency into build.zig.zon (usage: zig build vex-fetch -- <name>)");
    if (b.args) |args| {
        if (args.len >= 1) {
            const name = args[0];
            const cmd = b.addSystemCommand(&.{
                "zig",
                "run",
                "scripts/vex.zig",
                "--",
                "fetch",
                name,
            });
            cmd.stdio = .inherit;
            fetch_step.dependOn(&cmd.step);
        }
    }
}

fn ensureRegistryDeps(b: *std.Build) !void {
    const enabled = envBool(b, "VEX_REGISTRY") orelse true;
    if (!enabled) return;

    // Only fetch deps for enabled examples to avoid unnecessary downloads.
    if (exampleEnabled(b, "juce")) {
        try ensureRegistryDep(b, "juce");
    }
    if (exampleEnabled(b, "cmake-combo")) {
        try ensureRegistryDep(b, "fmt");
        try ensureRegistryDep(b, "spdlog");
    }
    if (exampleEnabled(b, "cmake-net")) {
        try ensureRegistryDep(b, "curl");
        try ensureRegistryDep(b, "zlib");
        try ensureRegistryDep(b, "mbedtls");
    }
    if (exampleEnabled(b, "json")) {
        try ensureRegistryDep(b, "nlohmann_json");
    }
}

fn ensureRegistryDep(b: *std.Build, name: []const u8) !void {
    if (zonHasDependency(b, name)) return;

    var child = std.process.Child.init(&.{
        "zig",
        "run",
        "scripts/vex.zig",
        "--",
        "fetch",
        name,
    }, b.allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }

    std.debug.print("\\n[vex] added dependency '{s}' to build.zig.zon; re-run zig build\\n", .{name});
    @panic("dependency added; re-run zig build");
}

fn zonHasDependency(b: *std.Build, name: []const u8) bool {
    const data = readFile(b, "build.zig.zon") catch return false;
    defer b.allocator.free(data);
    const needle = b.fmt(".{s}", .{name});
    return std.mem.indexOf(u8, data, needle) != null;
}

fn readFile(b: *std.Build, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const size = (try file.stat()).size;
    const buf = try b.allocator.alloc(u8, size);
    _ = try file.readAll(buf);
    return buf;
}

fn cacheWritable(b: *std.Build) bool {
    const cache_dir = std.process.getEnvVarOwned(b.allocator, "ZIG_GLOBAL_CACHE_DIR") catch null;
    defer if (cache_dir) |p| b.allocator.free(p);

    const path = if (cache_dir) |p| resolvePath(b, p) else defaultGlobalCachePath(b) orelse return false;
    // Avoid create/delete probes here because concurrent builds can race on the sentinel file.
    // If we can ensure the directory exists and open it, Zig can use it.
    if (std.fs.cwd().makePath(path)) |_| {} else |_| {}
    if (!std.fs.path.isAbsolute(path)) return false;
    if (std.fs.openDirAbsolute(path, .{})) |dir_const| {
        var dir = dir_const;
        defer dir.close();
        return true;
    } else |_| {
        return false;
    }
}

fn defaultGlobalCachePath(b: *std.Build) ?[]const u8 {
    const home = std.process.getEnvVarOwned(b.allocator, "HOME") catch null;
    defer if (home) |p| b.allocator.free(p);
    if (home == null) return null;
    return b.pathJoin(&.{ home.?, ".cache", "zig" });
}

fn resolvePath(b: *std.Build, path: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(path)) return path;
    return b.pathResolve(&.{ ".", path });
}

fn addBannerStep(b: *std.Build, name: []const u8, msg: []const u8) *std.Build.Step {
    const cmd = if (builtin.os.tag == .windows)
        &.{ "cmd.exe", "/c", b.fmt("echo {s}", .{msg}) }
    else
        &.{ "sh", "-c", b.fmt("printf '\\n\\033[1;32m%s\\033[0m\\n' \"{s}\"", .{msg}) };
    return vex_cmd.addCommandStep(b, b.fmt("banner_{s}", .{name}), cmd);
}

fn addInfoStep(b: *std.Build, name: []const u8, msg: []const u8) *std.Build.Step {
    const cmd = if (builtin.os.tag == .windows)
        &.{ "cmd.exe", "/c", b.fmt("echo {s}", .{msg}) }
    else
        &.{ "sh", "-c", b.fmt("printf '\\033[0;36m%s\\033[0m\\n' \"{s}\"", .{msg}) };
    return vex_cmd.addCommandStep(b, name, cmd);
}

fn parseExtraFlags(args: []const []const u8) []const []const u8 {
    if (args.len <= 1) return &.{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--")) {
            if (i + 1 >= args.len) return &.{};
            return args[i + 1 ..];
        }
    }
    return args[1..];
}

fn joinArgs(b: *std.Build, args: []const []const u8) []const u8 {
    if (args.len == 0) return "(none)";
    var buf = std.ArrayList(u8).init(b.allocator);
    for (args, 0..) |arg, idx| {
        if (idx > 0) buf.appendSlice(" ") catch unreachable;
        buf.appendSlice(arg) catch unreachable;
    }
    return buf.toOwnedSlice() catch unreachable;
}

fn buildCompileArgs(
    b: *std.Build,
    src: []const u8,
    out: []const u8,
    extra_flags: []const []const u8,
) []const []const u8 {
    var args = std.ArrayList([]const u8).init(b.allocator);
    args.appendSlice(&.{ "zig", "c++", src, "-o", out }) catch unreachable;
    args.appendSlice(extra_flags) catch unreachable;
    return args.toOwnedSlice() catch unreachable;
}

fn envBool(b: *std.Build, name: []const u8) ?bool {
    const value = std.process.getEnvVarOwned(b.allocator, name) catch null;
    defer if (value) |v| b.allocator.free(v);
    if (value == null) return null;
    const v = value.?;
    if (std.ascii.eqlIgnoreCase(v, "1") or
        std.ascii.eqlIgnoreCase(v, "true") or
        std.ascii.eqlIgnoreCase(v, "yes") or
        std.ascii.eqlIgnoreCase(v, "on"))
    {
        return true;
    }
    if (std.ascii.eqlIgnoreCase(v, "0") or
        std.ascii.eqlIgnoreCase(v, "false") or
        std.ascii.eqlIgnoreCase(v, "no") or
        std.ascii.eqlIgnoreCase(v, "off"))
    {
        return false;
    }
    return null;
}

fn envString(b: *std.Build, name: []const u8) ?[]const u8 {
    return std.process.getEnvVarOwned(b.allocator, name) catch null;
}

fn exampleEnabled(b: *std.Build, name: []const u8) bool {
    if (envString(b, "VEX_EXAMPLES")) |raw| {
        defer b.allocator.free(raw);
        var it = std.mem.splitScalar(u8, raw, ',');
        while (it.next()) |entry| {
            const trimmed = std.mem.trim(u8, entry, " \t\r\n");
            if (trimmed.len == 0) continue;
            if (std.ascii.eqlIgnoreCase(trimmed, name)) return true;
        }
        return false;
    }
    return true;
}

fn applyPresetToExample(example: *cpp.CppExample, preset: []const u8) void {
    example.configs = presets.presetConfigs(preset);
}

fn selectTarget(b: *std.Build) std.Build.ResolvedTarget {
    if (envString(b, "VEX_TARGET")) |target_str| {
        defer b.allocator.free(target_str);
        const query = std.Build.parseTargetQuery(.{ .arch_os_abi = target_str }) catch
            @panic("VEX_TARGET is invalid. Use a Zig target triple like x86_64-windows-gnu");
        return b.resolveTargetQuery(query);
    }
    if (builtin.os.tag == .windows) {
        if (envString(b, "VEX_WINDOWS_TOOLCHAIN")) |toolchain| {
            defer b.allocator.free(toolchain);
            if (std.ascii.eqlIgnoreCase(toolchain, "gnu")) {
                const query = std.Build.parseTargetQuery(.{ .arch_os_abi = "native-windows-gnu" }) catch
                    @panic("Failed to set Windows GNU toolchain target");
                return b.resolveTargetQuery(query);
            }
        }
    }
    return b.standardTargetOptions(.{});
}
