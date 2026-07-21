# Hello Zaza

The smallest complete example: a Zig executable and a C++ executable in one build graph.

## What it demonstrates

- `CppExample` with public and private include dirs and defines.
- `install_headers` and `export_cmake` on a minimal target.
- One run target that executes both artifacts.

## Prerequisites

Zig 0.14.1 or 0.15.2. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=hello-zaza zig build hello-zaza      # build both
ZAZA_EXAMPLES=hello-zaza zig build run-hello-zaza  # build and run both
```

## Expected output

```text
=== RUN: hello_zaza_cpp ===
lang: cpp
msg: hello from zig build system

=== RUN: hello_zaza_zig ===
lang: zig
msg: hello_zaza (zig)
```

## Notes

`hello-zaza` and `run-hello-zaza` are registered unconditionally, so they are present even under `ZAZA_EXAMPLES=none`.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
