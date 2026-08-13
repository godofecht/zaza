# CMake Subdirectory

Building an in-tree CMake subtree and linking it into a Zaza target. The
`add_subdirectory` migration path: keep a CMake component, move the top-level
build to Zaza.

## What it demonstrates

- `addCMakeSubdirectory` driving CMake to build `vendor/mathlib`, an existing
  CMake component left as-is.
- `CMakeSubdirectory.linkInto` adding the built archive, its headers, and the
  build-order dependency to a Zaza-built executable.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0, plus `cmake` on `PATH`. The Zig and CMake
toolchains must target the same architecture, so this runs on native
toolchains.

## Build and run

```bash
ZAZA_EXAMPLES=cmake-subdir zig build cmake-subdir      # build only
ZAZA_EXAMPLES=cmake-subdir zig build cmake-subdir-run  # build and run
```

## Expected output

```text
zaza top-level linked a CMake-built subdirectory: mathlib_square(7)=49
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
