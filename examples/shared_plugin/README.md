# Shared Plugin

A shared library loaded at runtime by a host executable through `dlopen`.

## What it demonstrates

- `b.addLibrary` with `.linkage = .dynamic`.
- Platform-specific artifact naming (`.dylib` / `.so` / `.dll`).
- Linking `dl` only on the platforms that need it.

## Prerequisites

Zig 0.14.1 or 0.15.2. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=shared-plugin zig build shared-plugin      # build both
ZAZA_EXAMPLES=shared-plugin zig build shared-plugin-run  # build and run the host
```

## Expected output

```text
plugin name: shared_plugin
plugin result: 42
```

## Notes

The run step passes the installed plugin path to the host as an argument.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
