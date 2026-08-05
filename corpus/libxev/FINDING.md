# Corpus finding: libxev

[libxev](https://github.com/mitchellh/libxev) is a Zig event loop that also ships
a **C API** (`include/xev.h`, static/dynamic `libxev` built from `src/c_api.zig`).
libxev is the corpus issue's "library / test / install path" candidate. Because
libxev is Zig, Zaza's C/C++ graph layer does not *build* it — the realistic angle
is Zaza **consuming libxev's C library** from a downstream C program.

That consumer works at the toolchain level, but the slice is **not yet
expressible as a `zaza.Target`**, for two independent reasons — one upstream, one
in Zaza. Both are recorded below with reproductions.

## Pinned upstream

| | |
|---|---|
| Repository | https://github.com/mitchellh/libxev |
| Commit | `9ce8e8e6ff89e583258a7f8e7adeeeaeae8611bf` |
| Requires | Zig **0.16.0** (`minimum_zig_version`), no third-party dependencies |
| Fetch/build | `./fetch.sh` → builds `libxev.a` + stages `xev.h` into `vendor/libxev` |

## What works — toolchain-level proof

`./proof.sh` compiles [`src/main.c`](src/main.c) with `zig cc` (the compiler
Zaza wraps), links libxev's C static library, and runs it:

```sh
zig cc -std=c99 -D_POSIX_C_SOURCE=199309L -I vendor/libxev \
    src/main.c vendor/libxev/libxev.a -o libxev_consumer
./libxev_consumer
# -> zaza+libxev slice: event loop ran, timer fired 1 time(s)
```

A real libxev event loop runs a timer to completion through a `zig cc`-built C
consumer linked against the libxev C library. Verified with the consumer built
by both Zig 0.15.2 and 0.16.0 against a `libxev.a` produced by 0.16.0.

## Finding 1 (upstream) — `xev.h` only compiles as C99

`xev.h` sizes its opaque structs with `const size_t` array bounds:

```c
const size_t XEV_SIZEOF_LOOP = 512;
...
typedef struct { XEV_ALIGN_T _pad; uint8_t data[XEV_SIZEOF_LOOP - sizeof(XEV_ALIGN_T)]; } xev_loop;
```

On x86_64-linux, `sizeof(max_align_t)` is **32** (for both `zig cc` and the
system `gcc`/`clang`). Two consequences:

- **C++ mode** (`-std=c++17`): `XEV_SIZEOF_THREADPOOL_BATCH` and
  `..._TASK` are `24`, so `data[24 - 32]` underflows —
  `error: array is too large (18446744073709551608 elements)`.
- **default gnu C mode**: `const size_t` is not a C constant expression, so the
  arrays become VLAs at file scope — `error: variably modified 'data' at file
  scope`.

Only `-std=c99` (which permits VLA-typed members and folds the bounds) compiles,
which is why libxev's own `examples/*.c` pass `-std=c99` — and why those examples
are gated off by default in libxev's build, so the header is never exercised by
libxev CI. Any C++ consumer, or any C consumer not forced to c99, fails to
include `xev.h` on this platform.

## Finding 2 (Zaza) — no way to build a C (non-C++) target

`zaza.Target` always emits a C++ standard flag and C++ options
(`build_lib/cpp_example.zig`, `cppCompileFlags`):

```
-std=c++<version>  -fexceptions  -frtti  -D_HAS_EXCEPTIONS=1
```

with `link_libcpp = true`. There is no option to select a **C** standard
(`-std=c99`) or to build a C-only target, and the C++ std flag is appended after
any user `cpp_flags`, so it cannot be overridden. Given Finding 1, that makes
`xev.h` uncompilable through the `zaza.Target` DSL, even though the underlying
`zig cc` handles it fine (proof above).

## Follow-up to make this a full slice

Add a C-language option to `zaza.Target` — e.g. `c_std: ?[]const u8` — that emits
`-std=c<std>`, drops the C++-only flags (`-frtti`, `-D_HAS_EXCEPTIONS`), and links
`libc` instead of `libc++`. With that, this overlay's `proof.sh` becomes an
ordinary `zaza.Target.executable` linking `vendor/libxev/libxev.a`, and libxev
graduates from a finding to a validated slice like `fmt` and `imgui`.

## Recorded environment

Zig 0.16.0 (libxev build) · Zig 0.15.2 / 0.16.0 (consumer) · gcc 13.3.0 · x86_64-linux.
