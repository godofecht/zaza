# Cross-Compile CLI

A nested build that targets a non-host triple, plus a report target that inspects the artifact.

## What it demonstrates

- Invoking a separate `build.zig` with `--build-file` and an option (`-Dtarget-triple`).
- `-report` naming for artifacts that cannot run on the host.

## Prerequisites

- A `./zig` wrapper script in the repo root. The nested build step invokes `./zig` by name. See the [setup script](../../setup.sh).
- `file(1)` on PATH for the report target.

## Build and run

```bash
ZAZA_EXAMPLES=cross-compile-cli zig build cross-compile-cli         # cross compile
ZAZA_EXAMPLES=cross-compile-cli zig build cross-compile-cli-report  # inspect the artifact
```

## Expected output

```text
examples/cross_compile_cli/zig-out/bin/cross_compile_cli: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, with debug_info, not stripped
```

## Notes

The default triple is `x86_64-linux-musl`. Change it with `-Dtarget-triple=` when running the nested build directly.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
