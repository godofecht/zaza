# Resources Bundle

A runtime asset staged into `zig-out/share` and read back by the executable.

## What it demonstrates

- `b.addInstallFileWithDir` for non-code outputs.
- Ordering the asset install ahead of the run step.
- Passing the staged path to the program as an argument.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=resources-bundle zig build resources-bundle      # build and stage
ZAZA_EXAMPLES=resources-bundle zig build resources-bundle-run  # build, stage, and run
```

## Expected output

```text
resource message: resource bundle ready
```

## Notes

The asset lands at `zig-out/share/resources_bundle/message.txt`.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
