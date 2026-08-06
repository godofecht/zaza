# target_kinds

Exercises every Zaza library `TargetKind` through the public API — **static**,
**shared**, **object**, and **interface** — plus an **executable** consumer, so
the example matrix covers all of them (zaza#41).

```sh
zig build target-kinds-run
# -> target_kinds: math_add(2, 3) = 5
```

`math_kinds.c` is built four ways (static/shared/object library, and an
interface library that carries only an include dir + a define); the executable
links the static library and calls it.
