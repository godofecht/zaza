# Package Consumer

A separate project that consumes the installed `package_producer` package from its manifest.

## What it demonstrates

- Reading `zig-out/share/zaza/package_math.json` at configure time.
- Deriving include paths, object files, and system libraries from the manifest instead of hardcoding them.
- A downstream build invoked with `--build-file`.

## Prerequisites

- A `./zig` wrapper script in the repo root. The root build invokes `./zig` by name. See the [setup script](../../setup.sh).

## Build and run

```bash
ZAZA_EXAMPLES=package-consumer zig build package-consumer      # install producer, then build consumer
ZAZA_EXAMPLES=package-consumer zig build package-consumer-run  # build and run
```

## Expected output

```text
package consumer result: 42
```

## Notes

The root target installs the producer first, so you do not need to run
`package-producer` separately. To build the consumer on its own, point it at an
existing install:

```bash
./zig build --build-file examples/package_consumer/build.zig run -Dpackage-prefix=zig-out
```

Use `./zig` rather than a bare `zig` here. The wrapper points both Zig cache
directories at the repo root, which is what the nested build expects.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
