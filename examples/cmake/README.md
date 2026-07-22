# CMake (Unwired)

An early CMake experiment that is not part of the build graph and does not compile.

## What it demonstrates

- Kept for reference only.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

This directory is **not** imported by the root `build.zig` and has no build target.
Its `build.zig` imports `../../zigcpp.zig` and `../../builder.zig`, which do not
exist at those paths, so it cannot be built as written.

For a working CMake-dependency example use [`cmake_shim`](../cmake_shim),
[`cmake_combo`](../cmake_combo), or [`cmake_net`](../cmake_net).

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
