# Generated Source

A custom command writes a `.cpp` file, which is then compiled as part of a normal target.

## What it demonstrates

- `custom_commands` running before compilation.
- `generated_source_files` alongside ordinary `source_files`.

## Prerequisites

- `sh` on PATH. The generator is a shell script.

## Build and run

```bash
ZAZA_EXAMPLES=generated-code zig build generated-code      # build only
ZAZA_EXAMPLES=generated-code zig build generated-code-run  # build and run
```

## Expected output

```text
generated code is working
```

## Notes

The generated file lands in `zig-out/gen/generated_message.cpp`.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
