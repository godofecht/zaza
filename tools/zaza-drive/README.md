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

## Watch mode

`--watch` keeps the driver resident and rebuilds whatever is dirty whenever a
source changes:

```
./zig-out/bin/zaza-drive --watch zig-out/build.manifest
```

It polls every 200ms. An unchanged poll is the same handful of stat calls as a
no-op, so watching an idle project costs almost nothing. Edit a file and the
rebuild happens within 200ms with no command to run.

Watch mode removes the command, not the work. A rebuild under `--watch` takes
the same time as a one-shot rebuild. See the performance note below for why the
rebuild itself cannot be made faster.

## The native compiler path

A rebuild is dominated by process startup, not compilation. Measured on an
Apple M4 Max, one trivial translation unit, median of 10 cold runs:

| | median |
|---|---|
| `zig version` (bare zig binary load) | ~14 ms |
| `zig c++ -c` | ~31 ms |
| `clang++ -c` (Apple clang) | ~15 ms |

The compile of one small unit is nil next to the load. The zig wrapper is
about twice the per-invocation cost of calling the system compiler directly. A
manifest with `compiler c++` uses the system default compiler, and on the same
16 unit workload the incremental rebuild drops from 127ms to 47ms.

`zig build drive-native` writes such a manifest:

```
zig build drive-native
./zig-out/bin/zaza-drive zig-out/build-native.manifest
```

This is a fast iteration path. The system compiler is a different compiler from
zig's bundled one, so it does not cross-compile and may differ in behaviour from
the canonical build. Release and cross builds should still go through
`zig build`, or through the faithful `zig build drive` manifest, which uses the
same `zig c++`. The native objects live in `.zaza-drive-native/` so the two
caches never mix.

## Why it is not faster still

Even with the system compiler, a rebuild pays that ~15ms load twice, once to
compile and once to link. A resident compiler server would seem to fix this by
keeping the compiler warm, but clang has no warm build-server mode here, and
every compile is a fresh process paying the load. A daemon can only reclaim the
driver's own startup, which is already about 2ms. Folding compile and link into
one call saves one load, but it discards the object for the recompiled unit,
which turns the next no-op into a full rebuild. That trade loses more than it
gains.

So watch mode and the native compiler are the wins available. Watch mode is a
convenience win: zero-command iteration, not faster builds.

## Manifest

Line-based. `compiler`, `cflags`, and `ldflags` appear once, `src` repeats.
Paths are relative to the working directory.

```
compiler zig c++
cflags -std=c++17 -g -Iinclude
ldflags -fuse-ld=mold
outdir .zaza-drive
bin app
src src/main.cpp
src src/unit_0.cpp
```

`ldflags` is optional and appended to the link step only, after the objects. It
is empty by default, which leaves Zig's own linker in place. See the linker note
below for when to set it.

## Status and limits

This is a working prototype that validates the direction.

- **Manifests are generated from a real target.** `CppExample.writeDriveManifest`
  emits one using the same `cppCompileFlags` the normal build uses, so the fast
  path and `zig build` compile with identical flags. `zig build drive-manifest`
  writes it to `zig-out/build.manifest`. End to end verified: emit the manifest
  for a target, drive it, run the binary, and a one-file edit recompiles only
  that file.
- **It builds on Zig 0.14.1, 0.15.2, and 0.16.0.** 0.16 moved the filesystem and
  process spawning under `std.Io` and changed how `main` receives arguments, so
  the driver comptime-dispatches those calls. Verified to build and drive
  correctly on all three, with the same no-op time.
- **It links the whole object set every time an object changes.** The `ldflags`
  manifest field selects the linker for that step. See the linker note.

## The linker

The relink processes every object on any change, so at very large object counts
the link becomes the cost. The obvious lever is a faster linker, so this was
measured. Linking 2000 objects on this machine (macOS):

| linker | time |
| --- | --- |
| Zig's own linker (default) | 651 ms |
| ld64.lld (`-fuse-ld=lld`) | 1125 ms |
| system ld (`-fuse-ld=/usr/bin/ld`) | 2274 ms |

Zig's linker is already the fastest available here, so swapping it in for lld or
the system linker loses. The default is correct, and the `ldflags` field exists
for the case where it is not: a very large link on Linux, where `-fuse-ld=mold`
is a real win. `zig cc` honors `-fuse-ld` and passes `-Wl,...` through, so the
field reaches the link.

A persistent or incremental linker was considered and is not worth building at
this scale. `zig cc -fincremental` does not apply to a link of prebuilt objects,
and there is no warm linker server to hand the objects to. The only saveable
cost is process startup, and that is already small next to the link itself. If
Zig's own incremental linker grows to cover this path, it becomes the right
answer; until then, the configurable linker is the honest improvement.

## Workflow

From the repo root, one command installs the driver and emits a manifest for
the hello_zaza C++ target:

```
zig build drive
```

That writes `zig-out/bin/zaza-drive` and `zig-out/build.manifest`. Then invoke
the driver directly for fast rebuilds:

```
./zig-out/bin/zaza-drive zig-out/build.manifest
```

The driver runs outside `zig build` on purpose. Running it through the build
system would reintroduce the startup cost it exists to avoid, so the fast path
is always a direct invocation of the binary. A no-op through the installed
driver is under 2ms.

To use it for another target, generate its manifest with
`CppExample.writeDriveManifest` the same way `build.zig` does, or hand-write the
format above.
