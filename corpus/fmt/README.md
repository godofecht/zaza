# fmt corpus slice

A slice of [{fmt}](https://github.com/fmtlib/fmt) `10.2.1` rebuilt through Zaza:
fmt's compiled library as a Zaza static-library target, plus a consumer that
links it and calls real fmt APIs.

```sh
./fetch.sh       # check out fmt 10.2.1 into vendor/ (git-ignored)
zig build        # build the fmt static-library slice + the consumer
zig build run    # build and run the consumer
```

The full recorded comparison — pinned ref, exact upstream (CMake) and Zaza
commands, artifacts, and known gaps — is in [`PROOF.md`](PROOF.md).
