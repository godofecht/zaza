# JSON (Zig Package Dependency)

nlohmann/json consumed as a Zig package dependency rather than through CMake.

## What it demonstrates

- `Dependency.type = .Zig` with `pkg_name` and `pkg_include`, resolved from `build.zig.zon`.
- A `view` target that serves an editable build-configuration page.

## Prerequisites

- The `nlohmann_json` entry in `build.zig.zon`. It is already committed. If it is missing, `ZAZA_REGISTRY` adds it automatically on the next build.

## Build and run

```bash
ZAZA_EXAMPLES=json zig build run   # build and run
ZAZA_EXAMPLES=json zig build view  # serve the build-configuration page
```

## Expected output

```text
{
    "awesome": true,
    "name": "C++ with Zig"
}
```

## Notes

The target's source is the repo-root `src/main.cpp`, not `examples/json/src/main.cpp`.
The `examples/json/src/main.cpp` file is a longer variant kept for reference.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
