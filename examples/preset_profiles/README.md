# Preset Profiles

An executable that prints the active `ZAZA_PRESET`, so preset selection is visible in output.

## What it demonstrates

- `ZAZA_PRESET` mapped to a `BuildConfig` list by `build_lib/presets.zig`.
- Presets: `debug`, `release`, `relwithdebinfo`, `minsizerel`, `asan`, `lto`.

## Prerequisites

Zig 0.14.1 or 0.15.2. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=preset-profiles zig build preset-profiles                  # build only
ZAZA_EXAMPLES=preset-profiles zig build preset-profiles-run              # default (debug)
ZAZA_EXAMPLES=preset-profiles ZAZA_PRESET=release zig build preset-profiles-run
```

## Expected output

```text
preset: debug
preset runtime ready
```

## Notes

Two presets are environment-dependent:

- `asan` fails to link when the AddressSanitizer runtime is unavailable.
- `lto` fails when the toolchain is not using LLD.

Both are toolchain constraints rather than example bugs.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
