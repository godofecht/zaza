# Find Package

Linking an installed library that Zaza resolved with `findPackage`, once through
pkg-config and once through CMake's own `find_package`.

## What it demonstrates

- `findPackage(b, "zlib", .{ .prefer = .pkg_config })` resolving an installed
  library through pkg-config.
- `findPackage(b, "zlib", .{ .prefer = .cmake, .cmake_name = "ZLIB", ... })`
  resolving the same library through CMake's `find_package`.
- The resolved include dirs and link inputs folded into a target's `packages`,
  with no hand-wired paths in the source or the build file.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. An installed zlib with either a `zlib.pc`
(pkg-config) or a CMake `ZLIB` config, plus `pkg-config` and `cmake` on `PATH`.

## Build and run

```bash
ZAZA_EXAMPLES=find-package zig build find-package  # build and run both resolvers
```

## Expected output

The same program runs twice, once per resolver:

```text
zaza+zlib: linked zlib 1.2.12, compressed 45 bytes to 52 and back
zaza+zlib: linked zlib 1.2.12, compressed 45 bytes to 52 and back
```

The version and byte counts depend on your installed zlib.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
