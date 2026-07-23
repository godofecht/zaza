# zaza-drive

A native, ninja-esque build driver. It exists to answer one question the
benchmark in `benchmarks/` raised: the no-op rebuild through `zig build` costs
~70ms, against Ninja's ~3ms, and almost all of that is `zig build` compiling
and running the build script and content-hashing its inputs on every
invocation. zaza-drive skips that.

It reads a manifest, stats the sources and their recorded header dependencies,
compiles only what is dirty, and links only when an object changed. A no-op is
a handful of `stat` calls and an exit.

## Measured

Same workload (16 translation units plus main), same machine, same compiler
(`zig c++` for all three lanes, so the comparison is build-system only). Run it
yourself with `./bench.sh`.

```
  phase        lane             min   median     max  ms
  --------------------------------------------------
  no-op        zaza-drive       2.2      2.3     3.1
  no-op        ninja            3.0      3.3     3.4
  no-op        zig build       67.5     69.7    73.7

  incremental  zaza-drive     109.1    110.4   112.3
  incremental  ninja          117.8    121.4   125.5
  incremental  zig build      105.1    106.1   118.2
```

zaza-drive beats Ninja on the no-op by a wide margin and edges it on the
incremental. On the incremental it is level with `zig build`, because once a
real translation unit recompiles and the binary relinks, the compiler does the
same work in every lane and that work dominates. The no-op is where orchestration
overhead is the whole cost, and that is where a minimal native driver wins.

Clean builds are not raced here. They are compile-bound, so every lane lands
within noise of the others.

## Correctness

Speed with wrong output is worthless. Each object is compiled with `-MMD -MF`,
which records the exact set of headers that translation unit included. On the
next run the driver reads that set and rebuilds an object when its source or any
recorded header is newer. Verified: editing a header shared by two of four units
rebuilds exactly those two and leaves the other two untouched. A stat-only driver
would miss the header edit entirely.

## Manifest

Line-based. `compiler` and `cflags` appear once, `src` repeats. Paths are
relative to the working directory.

```
compiler zig c++
cflags -std=c++17 -g -Iinclude
outdir .zaza-drive
bin app
src src/main.cpp
src src/unit_0.cpp
```

## Status and limits

This is a working prototype that validates the direction.

- **Manifests are generated from a real target.** `CppExample.writeDriveManifest`
  emits one using the same `cppCompileFlags` the normal build uses, so the fast
  path and `zig build` compile with identical flags. `zig build drive-manifest`
  writes it to `zig-out/build.manifest`. End to end verified: emit the manifest
  for a target, drive it, run the binary, and a one-file edit recompiles only
  that file.
- **It builds on Zig 0.14.1 and 0.15.2.** Zig 0.16 removed
  `std.process.argsAlloc` and changed how `main` receives arguments; the driver
  needs a small args shim before it compiles there. The driver it produces is a
  plain native binary, so the Zig version that builds it does not constrain what
  it drives.
- **It links the whole object set every time an object changes.** For very large
  link steps a persistent linker or incremental link would help. Not needed at
  this scale.

Build it with `zig build-exe main.zig -O ReleaseFast -femit-bin=zaza-drive` and
run `zaza-drive <manifest>`.
