# CMake Networking (curl + zlib + mbedtls)

Three interdependent CMake dependencies built from source and linked into one executable.

## What it demonstrates

- A dependency chain where curl is configured against the already-installed zlib and mbedtls.
- Per-config `link_files`, `link_libs`, and `link_frameworks`.

## Prerequisites

- `cmake` and `git` on PATH.
- Network access on the first run.
- Several minutes for the first build. mbedtls and curl are compiled from source.

## Build and run

```bash
ZAZA_EXAMPLES=cmake-net zig build cmake-net      # build only
ZAZA_EXAMPLES=cmake-net zig build cmake-net-run  # build and run
```

## Expected output

```text
cmake_net
curl: libcurl/8.6.0-DEV mbedTLS/3.6.2 zlib/1.3.1
zlib: 1.3.1
mbedtls: 3.6.2
```

## Notes

This example turns system commands on for itself, so `ZAZA_SYSTEM_CMDS=1` is not required.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
