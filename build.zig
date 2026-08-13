const std = @import("std");
const builtin = @import("builtin");

/// The Zaza public API, re-exported so downstream build files can reach the
/// stable surface through a path dependency on this repository:
///
/// ```zig
/// // build.zig.zon: .dependencies = .{ .zaza = .{ .path = "../.." } }
/// const zaza = @import("zaza").api;
/// ```
///
/// The external corpus overlays under `corpus/` consume Zaza this way, so they
/// build against the same API surface a real downstream consumer would.
pub const api = @import("build_lib/zaza.zig");
const json_example = @import("examples/json/build.zig");
const juce_example = @import("examples/juce/build.zig");
const cmake_shim_example = @import("examples/cmake_shim/build.zig");
const hello_zaza_example = @import("examples/hello_zaza/build.zig");
const cmake_combo_example = @import("examples/cmake_combo/build.zig");
const cmake_net_example = @import("examples/cmake_net/build.zig");
const proof_library_example = @import("examples/proof_library/build.zig");
const target_kinds_example = @import("examples/target_kinds/build.zig");
const generated_code_example = @import("examples/generated_code/build.zig");
const package_producer_example = @import("examples/package_producer/build.zig");
const mixed_stack_example = @import("examples/mixed_stack/build.zig");
const interface_object_graph_example = @import("examples/interface_object_graph/build.zig");
const test_workflows_example = @import("examples/test_workflows/build.zig");
const generated_headers_example = @import("examples/generated_headers/build.zig");
const shared_plugin_example = @import("examples/shared_plugin/build.zig");
const preset_profiles_example = @import("examples/preset_profiles/build.zig");
const resources_bundle_example = @import("examples/resources_bundle/build.zig");
const bindings_example = @import("examples/bindings/build.zig");
const benchmark_workflow_example = @import("examples/benchmark_workflow/build.zig");
const cxx20_modules_example = @import("examples/cxx20_modules/build.zig");
const wasm_wasi_example = @import("examples/wasm_wasi/build.zig");
const wasm_exports_example = @import("examples/wasm_exports/build.zig");
const zaza_juce_example = @import("examples/zaza-juce/build.zig");
const rust_interop_example = @import("examples/rust_interop/build.zig");
const bench_suite_example = @import("examples/bench_suite/build.zig");
const find_package_example = @import("examples/find_package/build.zig");
const cmake_subdir_example = @import("examples/cmake_subdir/build.zig");
const zaza_subproject_example = @import("examples/zaza_subproject/build.zig");
const universal_binary_example = @import("examples/universal_binary/build.zig");
const zaza_cmd = @import("build_lib/zaza_cmd.zig");
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

    // Lane preflight: warn clearly when the running Zig is outside the validated
    // lanes, and point at per-lane cache isolation so a 0.14 build and a 0.16
    // build don't share a stale cache. See docs/LANES.md and zaza.supported_lanes.
    if (!api.laneSupported(builtin.zig_version)) {
        const v = builtin.zig_version;
        std.log.warn(
            "Zig {d}.{d}.{d} is outside Zaza's validated lanes (0.14.x / 0.15.x / 0.16.x); builds may fail. " ++
                "Pin a supported lane, and isolate caches per lane with " ++
                "ZIG_LOCAL_CACHE_DIR=.zig-cache-{d}.{d} (see docs/LANES.md).",
            .{ v.major, v.minor, v.patch, v.major, v.minor },
        );
    }

    const system_cmds = b.option(bool, "system-cmds", "Enable git/cmake steps in build") orelse (envBool(b, "ZAZA_SYSTEM_CMDS") orelse false);
    const verbose = b.option(bool, "verbose", "Print build status messages") orelse true;
    const target = selectTarget(b);
    const optimize = b.standardOptimizeOption(.{});

    // Create the top `test` step up front so example test suites declared below
    // can hook onto it through test_suite.addTest. Its unit-test dependencies are
    // added further down.
    const test_step = b.step("test", "Run all tests");

    // Auto-fetch registry deps into build.zig.zon (can disable with ZAZA_REGISTRY=0)
    try ensureRegistryDeps(b);

    // Apply preset configs to examples (optional)
    if (zaza_cmd.envString(b, "ZAZA_PRESET")) |preset| {
        defer b.allocator.free(preset);
        applyPresetToExample(b, &cmake_combo_example.example, preset);
        applyPresetToExample(b, &cmake_net_example.example, preset);
        applyPresetToExample(b, &cmake_shim_example.example, preset);
        applyPresetToExample(b, &preset_profiles_example.example, preset);
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

    if (exampleEnabled(b, "zaza-juce")) {
        const zaza_juce_step = b.step("zaza-juce", "Build the Zaza JUCE audio synth example");
        try zaza_juce_example.buildWithTarget(b, target);
        zaza_juce_step.dependOn(b.getInstallStep());
    }

    // Rust interop: cargo builds a staticlib, Zig links it. Gated like the
    // other examples, since it needs cargo on PATH.
    if (exampleEnabled(b, "rust-interop")) {
        // addSteps registers the rust-interop and rust-interop-run top-level
        // steps itself.
        _ = rust_interop_example.addSteps(b, target, optimize);
    }

    const hello_step = b.step("hello-zaza", "Build hello_zaza (Zig + C++ via Zaza)");
    const hello_artifacts = try hello_zaza_example.addArtifacts(b, target, optimize);
    hello_step.dependOn(&b.addInstallArtifact(hello_artifacts.zig_exe, .{}).step);
    hello_step.dependOn(&b.addInstallArtifact(hello_artifacts.cpp_exe, .{}).step);

    const hello_run_zig = b.addRunArtifact(hello_artifacts.zig_exe);
    const hello_run_cpp = b.addRunArtifact(hello_artifacts.cpp_exe);
    const hello_run_step = b.step("run-hello-zaza", "Run both hello_zaza executables");
    hello_run_step.dependOn(&hello_run_zig.step);
    hello_run_step.dependOn(&hello_run_cpp.step);

    if (exampleEnabled(b, "proof-library")) {
        try proof_library_example.build(b, target, optimize);
    }

    if (exampleEnabled(b, "target-kinds")) {
        try target_kinds_example.build(b, target, optimize);
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
            "ZAZA_EXAMPLES=package-producer",
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

    if (exampleEnabled(b, "test-workflows")) {
        _ = test_workflows_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "bench-suite")) {
        bench_suite_example.addSteps(b, target);
    }

    if (exampleEnabled(b, "find-package")) {
        find_package_example.addSteps(b, target);
    }

    if (exampleEnabled(b, "cmake-subdir")) {
        cmake_subdir_example.addSteps(b, target);
    }

    if (exampleEnabled(b, "zaza-subproject")) {
        zaza_subproject_example.addSteps(b, target);
    }

    if (exampleEnabled(b, "generated-headers")) {
        _ = generated_headers_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "shared-plugin")) {
        _ = shared_plugin_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "preset-profiles")) {
        try preset_profiles_example.build(b, target, optimize);
    }

    if (exampleEnabled(b, "cross-compile-cli")) {
        const cross_build = b.addSystemCommand(&.{
            "./zig",
            "build",
            "--build-file",
            "examples/cross_compile_cli/build.zig",
            "cross-compile-cli",
            "-Dtarget-triple=x86_64-linux-musl",
        });
        cross_build.stdio = .inherit;
        const cross_step = b.step("cross-compile-cli", "Cross compile a CLI for x86_64-linux-musl");
        cross_step.dependOn(&cross_build.step);

        const inspect = b.addSystemCommand(&.{
            "file",
            "examples/cross_compile_cli/zig-out/bin/cross_compile_cli",
        });
        inspect.stdio = .inherit;
        inspect.step.dependencies.append(&cross_build.step) catch unreachable;
        const inspect_step = b.step("cross-compile-cli-report", "Inspect the cross compiled CLI artifact");
        inspect_step.dependOn(&inspect.step);
    }

    if (exampleEnabled(b, "resources-bundle")) {
        _ = resources_bundle_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "bindings")) {
        _ = bindings_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "universal-binary")) {
        _ = universal_binary_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "benchmark-workflow")) {
        _ = benchmark_workflow_example.addSteps(b, target, optimize);
    }

    if (exampleEnabled(b, "cxx20-modules")) {
        _ = cxx20_modules_example.addSteps(b);
    }

    if (exampleEnabled(b, "wasm-wasi")) {
        _ = wasm_wasi_example.addSteps(b, optimize);
    }

    if (exampleEnabled(b, "wasm-exports")) {
        _ = wasm_exports_example.addSteps(b, optimize);
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
            std.debug.print("[cmake-shim] skipped: system-cmds=false. Run with -Dsystem-cmds=true or ZAZA_SYSTEM_CMDS=1 to enable.\n", .{});
        }
        if (system_cmds) {
            cmake_shim_example.example.enable_system_commands = true;
            const cmake_check = zaza_cmd.addCommandStep(b, "cmake-version", &.{"cmake", "--version"});
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
    
    // zaza-drive fast path: the native driver in tools/zaza-drive rebuilds a
    // target without the Zig build runner on the hot path, which is much faster
    // on no-op and incremental rebuilds. See tools/zaza-drive/README.md.
    //
    // The driver has to run outside `zig build` to skip its startup cost, so
    // the workflow is two commands. `zig build drive` installs the driver
    // binary and emits a manifest; then you invoke the driver directly:
    //
    //   zig build drive
    //   ./zig-out/bin/zaza-drive zig-out/build.manifest
    //   ./zig-out/bin/zaza-drive --watch zig-out/build.manifest   # auto-rebuild
    //
    // The manifest describes the hello_zaza C++ target with the exact flags
    // buildWithTarget uses, so the fast path compiles identically.
    {
        const wf = b.addWriteFiles();

        // Faithful manifest: same zig c++ compiler as the normal build.
        const manifest = try hello_zaza_example.cpp_example.writeDriveManifest(b, false);
        const mpath = wf.add("build.manifest", manifest);
        const install_manifest = b.addInstallFileWithDir(mpath, .prefix, "build.manifest");

        // Native manifest: the system c++, which starts about twice as fast and
        // roughly halves an incremental rebuild. A different compiler from the
        // canonical build, so it is a fast iteration path.
        const manifest_native = try hello_zaza_example.cpp_example.writeDriveManifest(b, true);
        const mpath_native = wf.add("build-native.manifest", manifest_native);
        const install_manifest_native = b.addInstallFileWithDir(mpath_native, .prefix, "build-native.manifest");

        // The driver is cross-version, so it compiles under whatever Zig runs
        // this build. Installed to zig-out/bin so it can be invoked directly.
        const driver = b.addExecutable(.{
            .name = "zaza-drive",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/zaza-drive/main.zig"),
                .target = target,
                .optimize = .ReleaseFast,
            }),
        });
        driver.root_module.addImport("compat", b.createModule(.{
            .root_source_file = b.path("build_lib/compat.zig"),
        }));
        const install_driver = b.addInstallArtifact(driver, .{});

        const manifest_step = b.step("drive-manifest", "Emit a zaza-drive manifest into zig-out/");
        manifest_step.dependOn(&install_manifest.step);

        const drive_step = b.step("drive", "Install zaza-drive and the faithful (zig c++) manifest");
        drive_step.dependOn(&install_manifest.step);
        drive_step.dependOn(&install_driver.step);

        const drive_native_step = b.step("drive-native", "Install zaza-drive and a native (system c++) manifest, ~2x faster iteration");
        drive_native_step.dependOn(&install_manifest_native.step);
        drive_native_step.dependOn(&install_driver.step);
    }

    // zaza-lipo: a portable replacement for Apple's `lipo`, built on
    // build_lib/fatbinary.zig. `zig build zaza-lipo` installs it to
    // zig-out/bin so macOS universal binaries can be assembled on any host,
    // including a Linux runner with no Xcode. See tools/zaza-lipo.
    {
        const lipo = b.addExecutable(.{
            .name = "zaza-lipo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/zaza-lipo/main.zig"),
                .target = target,
                .optimize = .ReleaseFast,
            }),
        });
        lipo.root_module.addImport("fatbinary", b.createModule(.{
            .root_source_file = b.path("build_lib/fatbinary.zig"),
        }));
        lipo.root_module.addImport("compat", b.createModule(.{
            .root_source_file = b.path("build_lib/compat.zig"),
        }));
        const install_lipo = b.addInstallArtifact(lipo, .{});
        const lipo_step = b.step("zaza-lipo", "Install zaza-lipo, a portable lipo replacement (zaza#38)");
        lipo_step.dependOn(&install_lipo.step);
    }

    // zaza-import: generate a starter Zaza build.zig from a CMake project's
    // compile_commands.json (zaza#43). `zig build zaza-import` installs it to
    // zig-out/bin. See tools/zaza-import.
    {
        const importer = b.addExecutable(.{
            .name = "zaza-import",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/zaza-import/main.zig"),
                .target = target,
                .optimize = .ReleaseFast,
            }),
        });
        importer.root_module.addImport("compat", b.createModule(.{
            .root_source_file = b.path("build_lib/compat.zig"),
        }));
        const install_import = b.addInstallArtifact(importer, .{});
        const import_step = b.step("zaza-import", "Install zaza-import: CMake compile_commands.json -> starter Zaza build.zig (zaza#43)");
        import_step.dependOn(&install_import.step);
    }

    // Add clean tests that actually work (test_step was created up front).
    const clean_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/clean_tests.zig"),
            .target = b.graph.host,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(clean_tests).step);
    
    // Also add working simple tests
    const working_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/working_test.zig"),
            .target = b.graph.host,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(working_tests).step);

    // Wire up tests/
    const standalone_tests: []const []const u8 = &.{
        "build_lib/compat.zig",
        "build_lib/fatbinary.zig",
        "tests/test_string_split.zig",
        "tests/test_fetch_minimal.zig",
        "tests/test_cpp_targets.zig",
        "tests/test_dependency_ux.zig",
        "tests/test_workflows.zig",
        "tests/test_cmake_interop.zig",
        "tests/test_interop_hints.zig",
        "tests/test_interop_hints_full.zig",
        "tests/test_presets_full.zig",
        "tests/test_cpp_example_api.zig",
        "tests/test_public_api.zig",
        "tests/test_build_graph.zig",
        // TODO: test_zaza_juce.zig disabled - cpp_example exists in multiple modules (direct + via zaza_juce)
        // "tests/test_zaza_juce.zig",
    };
    for (standalone_tests) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = b.graph.host,
            }),
        });
        if (std.mem.eql(u8, path, "tests/test_cpp_targets.zig")) {
            t.root_module.addImport("cpp_example", b.createModule(.{
                .root_source_file = b.path("build_lib/cpp_example.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_dependency_ux.zig")) {
            t.root_module.addImport("cpp_example", b.createModule(.{
                .root_source_file = b.path("build_lib/cpp_example.zig"),
            }));
            t.root_module.addImport("zaza_cli", b.createModule(.{
                .root_source_file = b.path("scripts/zaza.zig"),
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
        if (std.mem.eql(u8, path, "tests/test_interop_hints.zig") or
            std.mem.eql(u8, path, "tests/test_interop_hints_full.zig"))
        {
            t.root_module.addImport("interop_hints", b.createModule(.{
                .root_source_file = b.path("build_lib/interop_hints.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_presets_full.zig")) {
            t.root_module.addImport("presets", b.createModule(.{
                .root_source_file = b.path("build_lib/presets.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_cpp_example_api.zig")) {
            t.root_module.addImport("cpp_example", b.createModule(.{
                .root_source_file = b.path("build_lib/cpp_example.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_public_api.zig")) {
            t.root_module.addImport("zaza", b.createModule(.{
                .root_source_file = b.path("build_lib/zaza.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_build_graph.zig")) {
            t.root_module.addImport("build_graph", b.createModule(.{
                .root_source_file = b.path("build_lib/build_graph.zig"),
            }));
        }
        if (std.mem.eql(u8, path, "tests/test_zaza_juce.zig")) {
            t.root_module.addImport("cpp_example", b.createModule(.{
                .root_source_file = b.path("build_lib/cpp_example.zig"),
            }));
            t.root_module.addImport("zaza_juce", b.createModule(.{
                .root_source_file = b.path("examples/zaza-juce/build.zig"),
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
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = b.graph.host,
            }),
        });
        t.root_module.addImport("dependencies", deps_mod);
        t.root_module.addImport("builder", builder_mod);
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    if (verbose) {
        std.debug.print("\n\x1b[1;34m=== ZAZA BUILD ===\x1b[0m\n", .{});
        std.debug.print("[phase] start\n", .{});
        if (system_cmds) {
            std.debug.print("[config] system-cmds=true (git/cmake enabled)\n", .{});
        } else {
            std.debug.print("[config] system-cmds=false (deps must already exist)\n", .{});
        }
        std.debug.print("[test] running\n", .{});
    }

    const example_matrix_step = b.step("example-matrix", "Run the verified example matrix sequentially");
    const matrix_targets: []const []const u8 = &.{
        "run-hello-zaza",
        "proof-library-run",
        "target-kinds-run",
        "generated-code-run",
        "package-consumer-run",
        "mixed-stack-run",
        "interface-object-graph-run",
        "zaza-subproject-run",
        "test-workflows-run",
        "bench-suite-run",
        "generated-headers-run",
        "shared-plugin-run",
        "preset-profiles-run",
        "cross-compile-cli-report",
        "resources-bundle-run",
        "bindings-run",
        "benchmark-workflow-run",
        "cxx20-modules-run",
        "wasm-wasi-report",
        "wasm-exports-run",
        "wasm-web-demo-smoke",
        "universal-binary-report",
    };
    var previous_matrix_step: ?*std.Build.Step = null;
    for (matrix_targets) |target_name| {
        // cxx20-modules drives a C++20-modules-capable clang++ (ZAZA_MODULES_CXX,
        // or the macOS Homebrew LLVM by default). Off macOS that default is
        // absent, so run it only when ZAZA_MODULES_CXX points at a clang++ (CI
        // sets it); skip otherwise. See #48.
        if (comptime builtin.os.tag != .macos) {
            if (std.mem.eql(u8, target_name, "cxx20-modules-run")) {
                if (zaza_cmd.envString(b, "ZAZA_MODULES_CXX")) |v| {
                    b.allocator.free(v);
                } else {
                    continue;
                }
            }
        }
        const nested = addNestedBuildStep(b, target_name);
        if (previous_matrix_step) |prev| {
            nested.dependencies.append(prev) catch unreachable;
        }
        example_matrix_step.dependOn(nested);
        previous_matrix_step = nested;
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
        std.debug.print("[build] outputs in zig-out/bin (json_example_Debug, hello_zaza_*)\n", .{});
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

    // Registry fetch: zig build zaza-fetch -- <name>
    const fetch_step = b.step("zaza-fetch", "Fetch a dependency into build.zig.zon (usage: zig build zaza-fetch -- <name>)");
    if (b.args) |args| {
        if (args.len >= 1) {
            const name = args[0];
            const cmd = b.addSystemCommand(&.{
                "zig",
                "run",
                "scripts/zaza.zig",
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
    const enabled = envBool(b, "ZAZA_REGISTRY") orelse true;
    if (!enabled) return;

    // Only fetch deps for enabled examples to avoid unnecessary downloads.
    if (exampleEnabled(b, "juce")) {
        try ensureRegistryDep(b, "juce");
    }
    if (exampleEnabled(b, "zaza-juce")) {
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
    // Already pinned in build.zig.zon (url + hash) means it resolves reproducibly
    // from the cache; nothing to fetch. Still confirm the lock agrees with the
    // manifest before trusting the build (zaza#45).
    if (zonHasDependency(b, name)) {
        try verifyLockedHash(b, name);
        return;
    }

    // Offline / cache-validation mode: do not reach the network. A dependency
    // that is not already pinned is an error, so a fresh clone can be validated
    // as fully vendored before it is trusted to build without network. (zaza#45)
    if (envBool(b, "ZAZA_OFFLINE") orelse false) {
        std.log.err(
            "offline: dependency '{s}' is not pinned in build.zig.zon and ZAZA_OFFLINE=1.\n" ++
                "  package:     {s}\n" ++
                "  source:      the Zaza registry (scripts/zaza.zig fetch {s})\n" ++
                "  remediation: run once online (unset ZAZA_OFFLINE) to pin it into build.zig.zon, then commit the lock.",
            .{ name, name, name },
        );
        return error.DependencyNotAvailableOffline;
    }

    // b.run exists in every supported Zig and fails the build on a non-zero
    // exit, so it replaces a hand-rolled Child. 0.16 removed Child.init and
    // moved spawning under std.Io.
    _ = b.run(&.{
        "zig",
        "run",
        "scripts/zaza.zig",
        "--",
        "fetch",
        name,
    });

    std.debug.print("\n[zaza] added dependency '{s}' to build.zig.zon; re-run zig build\n", .{name});
    @panic("dependency added; re-run zig build");
}

fn zonHasDependency(b: *std.Build, name: []const u8) bool {
    const data = readFile(b, "build.zig.zon") catch return false;
    defer b.allocator.free(data);
    const needle = b.fmt(".{s}", .{name});
    return std.mem.indexOf(u8, data, needle) != null;
}

// Fail the build when zaza.lock records a different hash than build.zig.zon for
// a pinned dependency, so a hand-edited manifest cannot drift from the committed
// lock unnoticed (zaza#45). The guard is deliberately lenient: a missing lock,
// an unparseable lock, or a dependency the lock does not yet record are all left
// to `zaza lock --check`, which is the strict CI gate. Only a genuine hash
// disagreement stops the build here.
fn verifyLockedHash(b: *std.Build, name: []const u8) !void {
    const lock = readFile(b, "zaza.lock") catch return;
    defer b.allocator.free(lock);

    const manifest_hash = zonDependencyHash(b, name) orelse return;
    defer b.allocator.free(manifest_hash);

    var parsed = std.json.parseFromSlice(std.json.Value, b.allocator, lock, .{}) catch return;
    defer parsed.deinit();

    const packages = parsed.value.object.get("packages") orelse return;
    const entry = packages.object.get(name) orelse return;
    const locked = if (entry.object.get("hash")) |h| h.string else return;

    if (!std.mem.eql(u8, locked, manifest_hash)) {
        std.log.err(
            "zaza.lock is out of sync with build.zig.zon for '{s}'.\n" ++
                "  package:     {s}\n" ++
                "  manifest:    {s}\n" ++
                "  lock:        {s}\n" ++
                "  remediation: run `zig run scripts/zaza.zig -- lock` to regenerate the lock, then commit it.",
            .{ name, name, manifest_hash, locked },
        );
        return error.LockHashMismatch;
    }
}

// Read a pinned dependency's `.hash` out of build.zig.zon, bounded to that
// dependency's own block so it never reads a neighbour's hash. Returns null when
// the dependency or its hash is absent. The result is owned by the caller.
fn zonDependencyHash(b: *std.Build, name: []const u8) ?[]const u8 {
    const data = readFile(b, "build.zig.zon") catch return null;
    defer b.allocator.free(data);

    const marker = b.fmt(".{s} = .{{", .{name});
    const marker_idx = std.mem.indexOf(u8, data, marker) orelse return null;
    const block_start = marker_idx + marker.len;
    const block_end = zonMatchingBrace(data, block_start) orelse return null;
    const block = data[block_start..block_end];

    const key = ".hash = \"";
    const key_idx = std.mem.indexOf(u8, block, key) orelse return null;
    const value_start = key_idx + key.len;
    const rest = block[value_start..];
    const value_end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return b.allocator.dupe(u8, rest[0..value_end]) catch null;
}

// Index of the `}` that closes the block starting just after an opening `{`.
fn zonMatchingBrace(data: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var i = start;
    while (i < data.len) : (i += 1) {
        switch (data[i]) {
            '{' => depth += 1,
            '}' => {
                if (depth == 0) return i;
                depth -= 1;
            },
            else => {},
        }
    }
    return null;
}

fn readFile(b: *std.Build, path: []const u8) ![]u8 {
    // Zig 0.16 moved the filesystem under std.Io, so opening needs the build
    // graph's Io handle. Only the taken branch is analysed.
    if (comptime !@hasDecl(std.fs, "cwd")) {
        return std.Io.Dir.cwd().readFileAlloc(b.graph.io, path, b.allocator, .unlimited);
    }
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const size = (try file.stat()).size;
    const buf = try b.allocator.alloc(u8, size);
    _ = try file.readAll(buf);
    return buf;
}

fn cacheWritable(b: *std.Build) bool {
    const cache_dir = zaza_cmd.envString(b, "ZIG_GLOBAL_CACHE_DIR");
    defer if (cache_dir) |p| b.allocator.free(p);

    const path = if (cache_dir) |p| resolvePath(b, p) else defaultGlobalCachePath(b) orelse return false;
    // Avoid create/delete probes here because concurrent builds can race on the sentinel file.
    // If we can ensure the directory exists and open it, Zig can use it.
    if (!std.fs.path.isAbsolute(path)) return false;
    // Zig 0.16 moved the filesystem under std.Io. Both branches only probe
    // whether the cache directory can be created and opened.
    if (comptime @hasDecl(std.fs, "cwd")) {
        if (std.fs.cwd().makePath(path)) |_| {} else |_| {}
        if (std.fs.openDirAbsolute(path, .{})) |dir_const| {
            var dir = dir_const;
            defer dir.close();
            return true;
        } else |_| {
            return false;
        }
    } else {
        // createDirPathOpen is the whole probe in one call: it creates any
        // missing parents and hands back the open directory.
        const io = b.graph.io;
        var dir = std.Io.Dir.cwd().createDirPathOpen(io, path, .{}) catch return false;
        dir.close(io);
        return true;
    }
}

fn defaultGlobalCachePath(b: *std.Build) ?[]const u8 {
    const home = zaza_cmd.envString(b, "HOME");
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
    return zaza_cmd.addCommandStep(b, b.fmt("banner_{s}", .{name}), cmd);
}

fn addInfoStep(b: *std.Build, name: []const u8, msg: []const u8) *std.Build.Step {
    const cmd = if (builtin.os.tag == .windows)
        &.{ "cmd.exe", "/c", b.fmt("echo {s}", .{msg}) }
    else
        &.{ "sh", "-c", b.fmt("printf '\\033[0;36m%s\\033[0m\\n' \"{s}\"", .{msg}) };
    return zaza_cmd.addCommandStep(b, name, cmd);
}

fn addNestedBuildStep(b: *std.Build, target_name: []const u8) *std.Build.Step {
    const run = b.addSystemCommand(&.{ "./zig", "build", target_name });
    run.setName(b.fmt("matrix-{s}", .{target_name}));
    run.stdio = .inherit;
    return &run.step;
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
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    for (args, 0..) |arg, idx| {
        if (idx > 0) buf.appendSlice(b.allocator, " ") catch unreachable;
        buf.appendSlice(b.allocator, arg) catch unreachable;
    }
    return buf.toOwnedSlice(b.allocator) catch unreachable;
}

fn buildCompileArgs(
    b: *std.Build,
    src: []const u8,
    out: []const u8,
    extra_flags: []const []const u8,
) []const []const u8 {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    args.appendSlice(b.allocator, &.{ "zig", "c++", src, "-o", out }) catch unreachable;
    args.appendSlice(b.allocator, extra_flags) catch unreachable;
    return args.toOwnedSlice(b.allocator) catch unreachable;
}

fn envBool(b: *std.Build, name: []const u8) ?bool {
    const value = zaza_cmd.envString(b, name);
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

fn exampleEnabled(b: *std.Build, name: []const u8) bool {
    if (zaza_cmd.envString(b, "ZAZA_EXAMPLES")) |raw| {
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

fn applyPresetToExample(b: *std.Build, example: *cpp.CppExample, preset: []const u8) void {
    example.configs = presets.resolvePreset(b, preset);
}

fn selectTarget(b: *std.Build) std.Build.ResolvedTarget {
    if (zaza_cmd.envString(b, "ZAZA_TARGET")) |target_str| {
        defer b.allocator.free(target_str);
        const query = std.Build.parseTargetQuery(.{ .arch_os_abi = target_str }) catch
            @panic("ZAZA_TARGET is invalid. Use a Zig target triple like x86_64-windows-gnu");
        return b.resolveTargetQuery(query);
    }
    if (builtin.os.tag == .windows) {
        if (zaza_cmd.envString(b, "ZAZA_WINDOWS_TOOLCHAIN")) |toolchain| {
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
