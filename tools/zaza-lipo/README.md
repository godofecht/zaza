# zaza-lipo

A portable replacement for the parts of Apple's `lipo` that a build needs. It
creates, inspects, and thins macOS universal (fat) binaries using
[`build_lib/fatbinary.zig`](../../build_lib/fatbinary.zig), so combining
per-arch Mach-O slices works on any host, a Linux CI runner included, with no
`lipo` and no Xcode.

## Build

```sh
zig build zaza-lipo        # installs zig-out/bin/zaza-lipo
```

## Use

```sh
# Combine an x86_64 and an arm64 build into one universal binary.
zaza-lipo create -arch x86_64 app_x86 -arch arm64 app_arm -output app

# List the architectures in a file.
zaza-lipo info app

# Pull a single arch back out.
zaza-lipo thin app arm64 -output app_arm
```

Arch names are `x86_64` and `arm64` (`aarch64` is accepted for the latter).

## Compatibility

The output is the same fat format `lipo -create` writes, so `lipo -info`,
`lipo -thin`, and the macOS loader all accept it. Verified on macOS against the
system tool: `lipo -info` reads the archs, `lipo -thin` extracts each slice
byte-identical to its input, and a combined executable runs.

This tool is part of zaza#38 (macOS universal binaries). The remaining pipeline
work is building both slices and calling the combiner at the install stage.
