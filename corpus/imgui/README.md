# imgui corpus slice

A slice of [Dear ImGui](https://github.com/ocornut/imgui) `1.87` (as vendored in
[zig-gamedev](https://github.com/zig-gamedev/zig-gamedev)) rebuilt through Zaza:
the renderer-independent ImGui core as a Zaza static-library target, plus a
headless consumer that renders a frame and reads back its draw data — no GPU or
windowing backend required.

```sh
./fetch.sh       # sparse-checkout the imgui slice into vendor/ (git-ignored)
zig build        # build the imgui static-library slice + the consumer
zig build run    # build and run the headless consumer
```

The full recorded comparison — pinned commit, exact upstream and Zaza commands,
artifacts, and known gaps — is in [`PROOF.md`](PROOF.md).
