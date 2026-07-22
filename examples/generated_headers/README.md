# Generated Header

A custom command writes a header, a static library includes it, and an executable links the library.

## What it demonstrates

- Generated headers wired into the include path of two downstream targets.
- Ordering a generated file ahead of both the library and the executable.

## Prerequisites

- `sh` on PATH. The generator is a shell script.

## Build and run

```bash
ZAZA_EXAMPLES=generated-headers zig build generated-headers      # build only
ZAZA_EXAMPLES=generated-headers zig build generated-headers-run  # build and run
```

## Expected output

```text
generated header is working
```

## Notes

The generated file lands in `zig-out/gen/generated_message.hpp`.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
