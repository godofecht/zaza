# C++20 Modules

A real C++20 named-module pipeline: precompile, compile, link.

## What it demonstrates

- Explicit `.pcm` and object generation as separate command steps.
- Choosing a compiler per target rather than assuming `zig c++`.

## Prerequisites

- A `clang++` with usable C++20 module support. The default path is `/opt/homebrew/opt/llvm/bin/clang++`.
- Override it with `ZAZA_MODULES_CXX=/path/to/clang++`.

## Build and run

```bash
ZAZA_EXAMPLES=cxx20-modules zig build cxx20-modules      # build only
ZAZA_EXAMPLES=cxx20-modules zig build cxx20-modules-run  # build and run
```

## Expected output

```text
modules add: 42
modules mul_add: 42
```

## Notes

This example intentionally does not use `zig c++`. On the machines this was
verified on, `zig c++` rejects `-x c++-module` and ignores `-fmodule-output`,
so the example uses a compiler that supports the flow instead of pretending
otherwise.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
