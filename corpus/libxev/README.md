# libxev corpus slice (finding)

[libxev](https://github.com/mitchellh/libxev)'s C API, consumed from a downstream
C program. The consumer builds, links, and runs against libxev's C static library
through Zaza's `zig cc` toolchain — but the slice is **not yet expressible as a
`zaza.Target`** because of an upstream header quirk and a missing C-language
option in Zaza.

```sh
./fetch.sh    # build libxev.a + stage xev.h (requires Zig 0.16)
./proof.sh    # zig cc -std=c99 build of the consumer, linked + run
# -> zaza+libxev slice: event loop ran, timer fired 1 time(s)
```

See [`FINDING.md`](FINDING.md) for the full analysis: why `xev.h` only compiles as
C99, why `zaza.Target` can't emit that today, and the one-option follow-up that
would turn this into a validated slice.
