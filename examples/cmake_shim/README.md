# CMake Shim

A single CMake dependency (nlohmann/json) cloned, configured, built, and installed by the Zaza graph.

## What it demonstrates

- `Dependency.type = .CMake` with `deps_build_system = .CMake` and `main_build_system = .Zig`.
- The smallest complete CMake interop path in the repo.

## Prerequisites

- `cmake` and `git` on PATH.
- `ZAZA_SYSTEM_CMDS=1`. Without it the target prints a skip notice and does nothing.
- Network access on the first run.

## Build and run

```bash
ZAZA_EXAMPLES=cmake-shim ZAZA_SYSTEM_CMDS=1 zig build cmake-shim      # build only
ZAZA_EXAMPLES=cmake-shim ZAZA_SYSTEM_CMDS=1 zig build cmake-shim-run  # build and run
```

## Expected output

```text
{
    "awesome": true,
    "name": "C++ with Zig"
}
```

## Notes

`cmake-shim-run` and `cmake-install` are only registered when system commands are enabled.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
