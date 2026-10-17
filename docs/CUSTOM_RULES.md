# Per-source custom rules (Zaza)

Zaza's `CustomRule` is a tracked, per-input generator inspired by the
file-set rule introduced in CMake 4.5. This is deliberately a **subset**, not
the CMake rule/property/configurator/derived-file-set implementation.

A rule uses one `<SOURCE>` argument and one `<OUTPUT>` argument, plus an
optional `<GENERATOR>` argument. File arguments are tracked by Zig's build
graph; `<OUTPUT>` uses `addOutputFileArg` and becomes a `LazyPath` used
directly by the target's compiler.

```zig
const zaza = @import("build_lib/zaza.zig");

const target = zaza.Target.executable(.{
    .name = "generated_app",
    .source_files = &.{"src/main.cpp"},
    .custom_rules = &.{
        .{
            .rule = .{
                .name = "compile_schema",
                .argv = &.{ "python3", "<GENERATOR>", "<SOURCE>", "<OUTPUT>" },
                .generator_file = "tools/compile_schema.py",
                .output_suffix = ".cpp",
            },
            .files = &.{"schema/example.json"},
        },
    },
    .enable_system_commands = true,
});
```

The generator executable must accept input and output paths in the given
positions. For the runnable example, see
[`examples/generated_code`](../examples/generated_code/README.md).

Unlike `custom_commands`, each input is an independent cached build step,
and the generated source is passed to Zig as a file dependency, rather than
pretending that a string path already exists. The generator itself can also
be tracked with `<GENERATOR>`. Rules can be copied with
`rule.derive(new_name, new_argv_or_null, new_suffix_or_null)`.

**Scope:** Zig-native compilation only. The generated sources must be C or
C++ files. The implementation does not yet support multiple outputs,
byproducts, depfiles, file-set metadata, scoped output visibility, arbitrary
pattern interpolation, CMake-exported rules, or CMake's configurator hooks.
If the target uses `.main_build_system = .CMake`, Zaza rejects a custom
rule rather than silently dropping it. Existing `custom_commands` and
`generated_source_files` are unchanged.

Run `zig build test` and the `generated-code` example on validated Zig
lanes after modifying the rule implementation. System commands must be
explicitly enabled for generated-code targets.
