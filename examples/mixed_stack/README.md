# Mixed C + C++ + Zig

A C static library, a C++ bridge library on top of it, and a Zig executable linking both.

## What it demonstrates

- Three languages in one target graph.
- A C++ library depending on a C library, both consumed from Zig.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=mixed-stack zig build mixed-stack      # build only
ZAZA_EXAMPLES=mixed-stack zig build mixed-stack-run  # build and run
```

## Expected output

```text
mixed stack result: 42
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
