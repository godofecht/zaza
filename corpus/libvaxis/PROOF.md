# Corpus proof: libvaxis

A target slice that consumes [libvaxis](https://github.com/rockorager/libvaxis)
— a pure-Zig terminal UI library — through a Zaza build file. This is the corpus
issue's "generated table workflow" candidate: libvaxis generates its Unicode
width/grapheme data at compile time (via its `uucode` dependency), and the
consumer exercises that generated table.

## Pure Zig is a first-class case

libvaxis has **no C or C++ sources**, so Zaza's C/C++ target DSL (`zaza.Target`)
does not apply here — and does not need to. Zaza is a Zig build system, so a Zig
library is consumed with the standard Zig build graph that Zaza is built on and
re-exports. The [`build.zig`](build.zig) in this slice is exactly what a Zaza
user writes for a Zig dependency: declare it, import its module, run a consumer.
"Pure Zig" is not an incompatibility — it is the Zig path working as intended.

## Pinned upstream

| | |
|---|---|
| Repository | https://github.com/rockorager/libvaxis |
| Commit | `5ca495f09f413c66789d9c5061359b941a8d82c2` (vaxis 0.6.0) |
| Requires | Zig **0.16.0**; deps `zigimg` and `uucode` (pinned transitively) |
| Generated data | `uucode` produces the Unicode width/grapheme tables at build time |

## Upstream build proof (libvaxis's own build)

libvaxis builds and tests itself through the Zig build system:

```sh
zig build          # in the libvaxis checkout; needs Zig 0.16
zig build test
```

## Zaza build proof

[`build.zig`](build.zig) declares the `vaxis` dependency and builds
[`src/main.zig`](src/main.zig), a consumer that calls `vaxis.gwidth.gwidth` —
which resolves grapheme display widths through the `uucode`-generated Unicode
data.

```sh
./fetch.sh         # only needed where Zig's fetcher can't reach GitHub (see below)
zig build run
```

Result — builds (compiling libvaxis, zigimg, and running the Unicode codegen) and
runs:

```
zaza+vaxis slice: gwidth ascii=1 wide=2 combining=1
zaza+vaxis slice: generated Unicode table OK
```

`ascii=1`, `wide=2` (East Asian wide `世`), and `combining=1` (`e` + U+0301) are
the correct widths, which means the whole graph — libvaxis, its `zigimg` and
`uucode` dependencies, and the build-time Unicode table — came through the Zig
build and works.

Artifacts:

| Artifact | Path |
|---|---|
| Consumer executable | `zig-out/bin/vaxis_consumer` |

## Fetching the dependencies

In a normal networked environment `zig build` fetches the git dependencies in
`build.zig.zon` itself; `fetch.sh` is not needed. It is provided for environments
where Zig's package fetcher cannot reach GitHub directly (e.g. a proxied sandbox):
it clones libvaxis, `zigimg`, and `uucode` at their pinned commits and `zig
fetch`es each into the local package cache, after which `zig build` resolves them
offline. This is the only difference from a stock consumer; the build file itself
is unmodified.

## Known gaps

- The consumer exercises the generated Unicode table, not libvaxis's interactive
  TTY rendering (which needs a real terminal). That keeps the proof deterministic
  and headless.
- Zaza contributes the Zig build system here, not its C/C++ graph layer; there is
  no C/C++ in libvaxis for that layer to act on.

## Recorded environment

Zig 0.16.0 · vaxis 0.6.0 · x86_64-linux.
