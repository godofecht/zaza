# Zig to C++ Bindings

A Zig executable calling into a C++ library across a C ABI wrapper.

## What it demonstrates

- A C++ class exposed through an `extern "C"` wrapper.
- A Zig module that wraps the C ABI in a small typed surface.
- Linking a static C++ library into a Zig executable.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=bindings zig build bindings      # build only
ZAZA_EXAMPLES=bindings zig build bindings-run  # build and run
```

## Expected output

```text
10 + 5 = 15
10 - 5 = 5
10 * 5 = 50
10 / 3 = 3.33
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
