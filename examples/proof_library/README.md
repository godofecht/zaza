# Proof Library

The plain case: a static C++ library with install/export metadata, plus an executable that links it.

## What it demonstrates

- `CppExample.staticLibrary` with `install_headers` and `export_cmake`.
- A hand-written `b.addExecutable` linking a `CppExample`-produced library.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=proof-library zig build proof-library      # build only
ZAZA_EXAMPLES=proof-library zig build proof-library-run  # build and run
```

## Expected output

```text
proof result: 42
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
