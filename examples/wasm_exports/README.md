# WebAssembly: Freestanding Exports

A freestanding `wasm32` module with exported functions, loaded from Node and from a browser page.

## What it demonstrates

- `entry = .disabled` and `rdynamic = true` for a freestanding export module.
- Staging `.wasm`, `.html`, and `.js` into `zig-out/www/wasm-exports`.
- A local static server used for both a smoke test and interactive serving.

## Prerequisites

- `node` on PATH for `wasm-exports-run`.

## Build and run

```bash
ZAZA_EXAMPLES=wasm-exports zig build wasm-exports           # build the module
ZAZA_EXAMPLES=wasm-exports zig build wasm-exports-run       # load it in Node and call exports
ZAZA_EXAMPLES=wasm-exports zig build wasm-web-demo          # stage the browser demo
ZAZA_EXAMPLES=wasm-exports zig build wasm-web-demo-smoke    # fetch the staged files over HTTP
ZAZA_EXAMPLES=wasm-exports zig build wasm-web-demo-serve    # serve at http://127.0.0.1:8000
```

## Expected output

```text
wasm add: 42
wasm mul_add: 42
```

## Notes

`wasm-web-demo-smoke` starts the server on port 8123, requests `/index.html`,
`/app.js`, and `/wasm_exports_demo.wasm`, then exits:

```text
Serving zig-out/www/wasm-exports at http://127.0.0.1:8123
```

`wasm-web-demo-serve` runs until interrupted.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
