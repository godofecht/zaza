# Rust Interop

A Cargo-built Rust static library linked into a Zig executable.

## What it demonstrates

- `build_lib/rust_example.zig`: cargo builds the staticlib, `zig build-obj` compiles the Zig side, and the system `cc` links them.
- Calling Rust functions across a C ABI from Zig.

## Prerequisites

- `cargo` on PATH.
- A `./zig` wrapper script in the repo root. The object-compile step invokes `./zig` by name. See the [setup script](../../setup.sh).
- macOS. The link step passes `-lSystem` and Apple frameworks.

## Build and run

```bash
ZAZA_EXAMPLES=rust-interop zig build rust-interop      # build only
ZAZA_EXAMPLES=rust-interop zig build rust-interop-run  # build and run
```

## Expected output

```text
=== Zaza Rust Interop Demo ===

rust_add(17, 25) = 42
rust_factorial(5)  = 120
rust_factorial(10) = 3628800
rust_strlen("Hello from Zig to Rust!") = 23

All Rust interop calls succeeded!
```

## Notes

The system linker is used deliberately: Zig 0.14's internal Mach-O linker
cannot parse Rust-produced archives. `ld: warning: ignoring duplicate libraries:
'-lSystem'` is expected and harmless.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
