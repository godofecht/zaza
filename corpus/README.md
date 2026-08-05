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
| [`fmt`](fmt) | ✅ CMake | ✅ static lib + linked consumer | See [`fmt/PROOF.md`](fmt/PROOF.md). |
| [`imgui`](imgui) (from `zig-gamedev`) | ✅ drop-in `c++`/`ar` | ✅ static lib + headless consumer | Dear ImGui core. The `zig-gamedev` candidate, reduced to the C/C++ part that needs no system GL. See [`imgui/PROOF.md`](imgui/PROOF.md). |
| [`imgui_glfw`](imgui_glfw) (from `zig-gamedev`) | ✅ drop-in `g++`/`ar` | ✅ static lib + windowed consumer | Dear ImGui + GLFW/OpenGL3 backends, linked against system GLFW/GL and run headless under Xvfb. The heavier glfw+imgui+GL graph. See [`imgui_glfw/PROOF.md`](imgui_glfw/PROOF.md). |
| [`libxev`](libxev) (lib/test install) | ✅ libxev's own build | ✅ C99 consumer links + runs | Consumes libxev's C API; motivated the `c_std` (C-language) option on `zaza.Target`. See [`libxev/PROOF.md`](libxev/PROOF.md). |
| [`libvaxis`](libvaxis) (generated table) | ✅ libvaxis's own build | ✅ Zig consumer builds + runs | Pure-Zig library with a build-time generated Unicode table; consumed with the standard Zig build graph. See [`libvaxis/PROOF.md`](libvaxis/PROOF.md). |

All five candidate slices — `fmt`, `imgui`, `imgui_glfw`, `libxev`, and
`libvaxis` — satisfy the issue's "done when": an external target slice with both
an upstream build proof and a Zaza build proof, documented with exact commands and
artifact locations.

## Findings

Corpus validation is as much about surfacing gaps as landing green slices. Both
findings below were closed by landing the slice they came from.

- **`libxev` (resolved)** — its C API header (`xev.h`) compiles only under
  `-std=c99` (it fails in C++ mode and in default gnu C mode where `max_align_t`
  is 32). `zaza.Target` used to compile every target as C++, so it could not build
  the consumer. That gap is now closed: `zaza.Target` gained a `c_std` option
  (compile as C, no RTTI/exceptions, link `libc`), and `libxev` is a validated
  slice. See [`libxev/PROOF.md`](libxev/PROOF.md).
- **`libvaxis` (resolved)** — first written off as "out of scope" because it is
  pure Zig with no C/C++ surface. That was wrong: Zaza is a Zig build system, so a
  Zig library is consumed with the standard Zig build graph Zaza is built on —
  Zaza's C/C++ DSL simply does not apply. `libvaxis` is a validated slice,
  including its build-time generated Unicode table. See [`libvaxis/PROOF.md`](libvaxis/PROOF.md).

### Is `szkkng/juzi` needed, or already solved by Zaza?

[`juzi`](https://github.com/szkkng/juzi) builds JUCE **audio plugins** (VST3, AU,
Standalone) **natively through the Zig build system** — it compiles the JUCE
modules with `addCSourceFiles` and assembles the plugin bundles (Info.plist,
PkgInfo, the macOS MH_DYLIB workaround) in pure Zig, with **no CMake**.

Zaza's JUCE support is a different thing: `zaza.JUCEApplication` **generates a
`CMakeLists.txt`** that calls `juce_add_gui_app` and then **drives JUCE's own
CMake** (it needs system commands enabled). So it builds a GUI **application** via
CMake, not audio **plugins** natively.

Verdict: **not already solved.** They overlap only at "use Zig tooling with JUCE."
juzi covers a capability Zaza does not have today — native (CMake-free) VST3/AU
plugin builds with bundle packaging. If Zaza wants that niche, juzi is the
reference design for a native `juce_add_plugin`-equivalent; until then juzi is
still necessary for anyone building plugins rather than GUI apps.

## Why fmt first

`fmt` is already in Zaza's registry and manifest, builds a genuine compiled
library (`src/format.cc`, `src/os.cc`) rather than a header-only shim, and has a
canonical CMake build to compare against — so it exercises the C/C++ graph layer
end to end (static library target → downstream executable that links it) with the
least incidental setup. It is the smallest honest proof that Zaza can stand in
for CMake on an external target slice.
