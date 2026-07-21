# Package Producer

A static library published with headers, an archive, a CMake config, and a Zaza package manifest.

## What it demonstrates

- `install_headers`, `export_cmake`, and `export_name` on a `staticLibrary`.
- The `zig-out/share/zaza/<name>.json` manifest format that `package_consumer` reads.

## Prerequisites

Zig 0.14.1 or 0.15.2. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=package-producer zig build package-producer      # build and install
ZAZA_EXAMPLES=package-producer zig build package-producer-run  # run the bundled demo
```

## Expected output

```text
package producer demo: 45
```

## Notes

The install produces:

```text
zig-out/include/package_math/package_math.hpp
zig-out/lib/libpackage_math_Debug.a
zig-out/cmake/package_math/package_mathConfig.cmake
zig-out/share/zaza/package_math.json
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
