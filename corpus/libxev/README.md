# libxev corpus slice

A slice that consumes [libxev](https://github.com/mitchellh/libxev)'s C API from a
downstream C program built through Zaza: [`src/main.c`](src/main.c) as a
`zaza.Target.executable` with `c_std = "99"`, linked against libxev's C static
library, driving a real event loop.

```sh
./fetch.sh       # build libxev.a + stage xev.h (requires Zig 0.16)
zig build run    # build the C consumer through Zaza, link libxev.a, run it
# -> zaza+libxev slice: event loop ran, timer fired 1 time(s)
```

The full recorded comparison — pinned commit, upstream and Zaza commands,
artifacts, the `c_std` option this slice motivated, and known gaps — is in
[`PROOF.md`](PROOF.md).
