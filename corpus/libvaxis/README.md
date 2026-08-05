# libvaxis corpus slice

A pure-Zig slice: [libvaxis](https://github.com/rockorager/libvaxis) (vaxis 0.6.0)
consumed through a Zaza build file. The consumer calls `vaxis.gwidth.gwidth`,
which resolves grapheme widths through the Unicode table libvaxis generates at
build time via its `uucode` dependency.

```sh
./fetch.sh       # only where Zig's fetcher can't reach GitHub (see PROOF.md)
zig build run
# -> zaza+vaxis slice: gwidth ascii=1 wide=2 combining=1
#    zaza+vaxis slice: generated Unicode table OK
```

libvaxis has no C/C++ sources, so Zaza's C/C++ target DSL does not apply — a Zig
library is consumed with the standard Zig build graph Zaza is built on. The full
recorded proof is in [`PROOF.md`](PROOF.md).
