# External corpus

Corpus validation proves Zaza's replacement value on real upstream projects,
not only the internal examples under [`../examples`](../examples). Each entry is
a *target slice*: a piece of a real repository rebuilt through Zaza's C/C++ graph
layer, with the upstream build and the Zaza build both recorded so the two can be
compared command for command.

This directory tracks [issue #46](https://github.com/godofecht/zaza/issues/46).

## How a slice is structured

Every slice is a self-contained overlay directory. It carries only Zaza build
files — never a vendored copy of the upstream sources:

```
corpus/<slice>/
  build.zig        # the slice expressed with the Zaza API
  build.zig.zon    # path dependency on the Zaza repo root
  fetch.sh         # checks the pinned upstream release out into vendor/ (git-ignored)
  src/             # any consumer/driver code the proof needs
  PROOF.md         # pinned ref, exact upstream + Zaza commands, artifacts, gaps
```

The overlay reaches the Zaza API through a path dependency, exactly the way an
out-of-tree consumer would:

```zig
// build.zig.zon
.dependencies = .{ .zaza = .{ .path = "../.." } },

// build.zig
const zaza = @import("zaza").api;
```

Manifest dependencies in the Zaza root are lazy, so an overlay only fetches what
its own targets consume — nothing else in Zaza's dependency set is pulled in.

## Running a slice

```sh
cd corpus/<slice>
./fetch.sh          # check out the pinned upstream release into vendor/
zig build run       # build the slice through Zaza and run its consumer
```

## Status

| Slice | Upstream proof | Zaza proof | Notes |
|-------|:--------------:|:----------:|-------|
| [`fmt`](fmt) | ✅ CMake | ✅ static lib + linked consumer | First landed slice. See [`fmt/PROOF.md`](fmt/PROOF.md). |
| `zig-gamedev` (glfw/imgui/bullet) | — | — | Candidate from #46. C/C++ sample dependency graph. Not started. |
| `libvaxis` (generated table) | — | — | Candidate from #46. Custom-command / generated-source proof. Not started. |
| `libxev` (lib/test install) | — | — | Candidate from #46. Library + test install/report path. Not started. |

`fmt` satisfies the issue's "done when": one external target slice has both an
upstream build proof and a Zaza build proof, documented with exact commands and
artifact locations. The remaining candidates are the next slices to land.

## Why fmt first

`fmt` is already in Zaza's registry and manifest, builds a genuine compiled
library (`src/format.cc`, `src/os.cc`) rather than a header-only shim, and has a
canonical CMake build to compare against — so it exercises the C/C++ graph layer
end to end (static library target → downstream executable that links it) with the
least incidental setup. It is the smallest honest proof that Zaza can stand in
for CMake on an external target slice.
