# Corpus proof: libxev

A target slice that consumes [libxev](https://github.com/mitchellh/libxev)'s
**C API** from a downstream C program built through Zaza. libxev is the corpus
issue's "library / test / install path" candidate. Because libxev itself is Zig,
Zaza does not compile it — the slice is Zaza **building and linking a C consumer**
against libxev's C static library.

This started as a finding: libxev's `xev.h` only compiles as C99, and Zaza had no
way to build a C (non-C++) target. It is now a validated slice, using the `c_std`
option added to `zaza.Target` for exactly this case.

## Pinned upstream

| | |
|---|---|
| Repository | https://github.com/mitchellh/libxev |
| Commit | `9ce8e8e6ff89e583258a7f8e7adeeeaeae8611bf` |
| Requires | Zig **0.16.0** (libxev's `minimum_zig_version`), no third-party deps |
| Fetch/build | `./fetch.sh` → builds `libxev.a` + stages `xev.h` into `vendor/libxev` |

## Upstream build proof (libxev's own build)

libxev's C static library is produced by its own Zig build (what `fetch.sh` runs):

```sh
zig build -Doptimize=ReleaseFast     # in the libxev checkout; needs Zig 0.16
# -> zig-out/lib/libxev.a, include/xev.h, share/pkgconfig/libxev.pc
```

Artifact: `vendor/libxev/libxev.a` (~4.5 MB).

## Zaza build proof

The slice is expressed in [`build.zig`](build.zig): [`src/main.c`](src/main.c) as
a `zaza.Target.executable` with `c_std = "99"`, linked against the staged
`libxev.a`. The consumer drives a real libxev event loop — a timer fires and the
loop returns when there is no more work.

```sh
zig build          # build the C consumer through Zaza and link libxev.a
zig build run      # build and run it
```

Result — builds and runs (verified under both Zig 0.15.2 and 0.16.0):

```
zaza+libxev slice: event loop ran, timer fired 1 time(s)
```

Artifacts:

| Artifact | Path |
|---|---|
| C consumer (Zaza) | `zig-out/bin/libxev_consumer_Release` |
| Zaza package manifest | `zig-out/share/zaza/libxev_consumer.json` |

## The `c_std` option this slice motivated

`zaza.Target` compiled every target as C++ — it always emitted `-std=c++NN` plus
`-frtti -fexceptions -D_HAS_EXCEPTIONS=1` and linked `libc++`. libxev's `xev.h`
does not survive that:

- **C++ mode**: its opaque `threadpool` struct sizes are `24`, and
  `sizeof(max_align_t)` is `32` on x86_64-linux, so `data[24 - 32]` underflows —
  `error: array is too large`.
- **default gnu C mode**: `const size_t` array bounds become VLAs at file scope —
  `error: variably modified 'data' at file scope`.

Only `-std=c99` compiles it, which is why libxev's own `examples/*.c` pass
`-std=c99` (and are gated off by default, so libxev CI never exercises the
header). The new option makes that expressible:

```zig
zaza.Target.executable(.{
    .name = "libxev_consumer",
    .source_files = &.{"src/main.c"},
    .c_std = "99",   // build as C99: -std=c99, no RTTI/exceptions, links libc
    ...
});
```

When `c_std` is set, the target is compiled with `-std=c<c_std>`, the C++-only
flags are dropped, and it links `libc` instead of `libc++`.

## Known gaps

- The slice consumes the prebuilt `libxev.a`; it does not rebuild libxev's Zig
  through Zaza (Zaza's layer is C/C++, not Zig).
- Only a timer watcher is exercised. libxev's async/file/process watchers would
  broaden the proof but add no new build-system coverage.
- The upstream header quirk is libxev's, not Zaza's; this slice works around it by
  building as C99. A fix upstream would be to make the sizes macros/enums and bump
  the threadpool sizes to at least `sizeof(max_align_t)`.

## Recorded environment

Zig 0.16.0 (libxev build) · Zig 0.15.2 / 0.16.0 (consumer) · x86_64-linux.
