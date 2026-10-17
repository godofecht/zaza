# Generated source through a reusable rule

This example uses a tracked per-source `CustomRule` to generate a C++ translation
unit. The generator script and input template are declared as file dependencies
and the generated output is a Zig `LazyPath` consumed by compilation. Only
the changed input's action needs to rerun.

```bash
ZAZA_EXAMPLES=generated-code zig build generated-code
ZAZA_EXAMPLES=generated-code zig build generated-code-run
```

Expected output: `generated code is working`.

The generated C++ file lives in Zig's managed cache (not `zig-out/gen`).
This example requires `sh` and `cp` on PATH. Existing `custom_commands`
and `generated_source_files` remain supported for other workflows.
