# WebAssembly: WASI

A `wasm32-wasi-musl` executable, validated as a real WebAssembly binary.

## What it demonstrates

- Resolving an explicit wasm target query inside the build file.
- `-report` naming for an artifact the host cannot execute directly.

## Prerequisites

- `node` on PATH for `wasm-wasi-report`.

## Build and run

```bash
ZAZA_EXAMPLES=wasm-wasi zig build wasm-wasi         # build the module
ZAZA_EXAMPLES=wasm-wasi zig build wasm-wasi-report  # validate the artifact
```

## Expected output

```text
wasm wasi valid
```

## Notes

The artifact is `zig-out/bin/wasm_wasi_demo.wasm`. Run it with any WASI runtime, for example `wasmtime`.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
