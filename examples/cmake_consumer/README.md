# CMake Consumer

A plain CMake project consuming a Zaza-built library through `find_package`. The
producer is `examples/package_producer`, which exports `package_math` as a CMake
package.

## What it demonstrates

- `export_cmake` producing a `find_package`-consumable package: the built
  library, an imported target in `package_mathConfig.cmake`, and a
  `package_mathConfigVersion.cmake`.
- A plain `CMakeLists.txt` doing `find_package(package_math 1.0 REQUIRED)` and
  `target_link_libraries(cmake_consumer PRIVATE package_math::package_math)`.
- The include coming from the imported target's interface, the symbols from its
  location, with no path written in the consumer.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0, plus `cmake` on `PATH`. The Zig and CMake
toolchains must target the same architecture, so this runs on native
toolchains. The exported library builds in release: a Zig Debug static library
carries UBSan runtime calls a non-Zig linker cannot resolve.

## Build and run

`verify.sh` builds and installs the producer, then configures, builds, and runs
the consumer:

```bash
sh examples/cmake_consumer/verify.sh
```

Set `ZIG` to pick a specific Zig (`ZIG=~/zig/0.14.1/zig sh examples/cmake_consumer/verify.sh`).

## Expected output

```text
cmake consumer linked zaza-built package_math: add(2,3)=5, mul_add(2,3,4)=10
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
