# Unity Build

Several sources compiled as one translation unit, the `CMAKE_UNITY_BUILD`
equivalent.

## What it demonstrates

- `unity_build = true` on a target with more than one source.
- Zaza generates one translation unit that includes each source, then compiles
  that single unit. Shared headers are parsed once instead of once per source,
  which speeds a cold build.
- The generated unit is written into the build cache, not the source tree.

Keep sources that rely on file-local state (anonymous namespaces, file-scope
`static`, macros that leak between files) out of a unity target: combining them
into one translation unit can make those collide.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=unity-build zig build unity-build      # build only
ZAZA_EXAMPLES=unity-build zig build unity-build-run  # build and run
```

## Expected output

```text
unity build: part_a() + part_b() = 7
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
