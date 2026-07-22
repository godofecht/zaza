# CMake Combo (fmt + spdlog)

Two CMake dependencies built and installed by the Zaza graph, then linked into a Zig-built executable.

## What it demonstrates

- Multiple CMake dependencies with an ordering constraint (spdlog configures against the installed fmt).
- `cmake_config.configure_args` and `install_prefix` per dependency.
- Per-config `link_files` pointing at the installed archives.

## Prerequisites

- `cmake` and `git` on PATH.
- Network access on the first run, to clone fmt and spdlog into `deps/`.

## Build and run

```bash
ZAZA_EXAMPLES=cmake-combo zig build cmake-combo      # build only
ZAZA_EXAMPLES=cmake-combo zig build cmake-combo-run  # build and run
```

## Expected output

```text
[2026-07-21 12:06:42.346] [info] hello from cmake_combo
```

## Notes

This example turns system commands on for itself, so `ZAZA_SYSTEM_CMDS=1` is not required.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
