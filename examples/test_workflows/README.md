# Workflow Modes

One executable exposed as three run modes that differ by argument, environment variable, and working directory.

## What it demonstrates

- `setCwd`, `setEnvironmentVariable`, and `addArg` per run step.
- A combined `-run` target plus per-mode targets.
- Reading a fixture file that only resolves under the right working directory.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=test-workflows zig build test-workflows              # build only
ZAZA_EXAMPLES=test-workflows zig build test-workflows-run          # all three modes
ZAZA_EXAMPLES=test-workflows zig build test-workflows-unit         # unit mode only
ZAZA_EXAMPLES=test-workflows zig build test-workflows-integration  # integration mode only
```

## Expected output

```text
workflow mode: smoke
workflow env: smoke
workflow fixture: workflow fixture ready
workflow mode: integration
workflow env: integration
workflow fixture: workflow fixture ready
workflow mode: unit
workflow env: unit
workflow fixture: workflow fixture ready
```

## Notes

The three modes run in parallel, so their output can interleave in a different order.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
