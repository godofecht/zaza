# universal_binary

Build a program for both macOS architectures and combine the slices into one
Mach-O universal (fat) binary.

```bash
ZAZA_EXAMPLES=universal-binary zig build universal-binary-report
```

That step builds the demo for `x86_64-macos` and `aarch64-macos`, combines the
two with [`zaza-lipo`](../../tools/zaza-lipo), installs the result to
`zig-out/bin/universal_binary_demo`, and runs `zaza-lipo info` on it.

Zig cross-compiles both slices from any host, and `zaza-lipo` combines them
without Apple's `lipo`, so the example builds and reports on Linux as well as on
macOS. Running the result needs a Mac; `chmod +x zig-out/bin/universal_binary_demo`
first, since it installs as a plain file.

This is the pipeline half of [zaza#38](https://github.com/godofecht/zaza/issues/38).
The combine step it uses (`build_lib/fatbinary.zig`) is verified against Apple's
`lipo` and the macOS loader in that module's own tests.
