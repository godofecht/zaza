# Corpus proof: imgui (zig-gamedev)

A target slice of [Dear ImGui](https://github.com/ocornut/imgui) as vendored in
[zig-gamedev](https://github.com/zig-gamedev/zig-gamedev), rebuilt through Zaza's
C/C++ graph layer. This is the corpus issue's `zig-gamedev` candidate, reduced to
the part that exercises the C/C++ graph without dragging in system GL/X11: the
renderer- and platform-independent Dear ImGui **core**.

## Pinned upstream

| | |
|---|---|
| Repository | https://github.com/zig-gamedev/zig-gamedev |
| Commit | `9af37ec05bbfe5164dafc4c741a7d35667bd09c5` |
| Slice | `samples/common/libs/imgui` — Dear ImGui **1.87** core |
| Sources | `imgui.cpp`, `imgui_draw.cpp`, `imgui_tables.cpp`, `imgui_widgets.cpp` (+ headers) |
| Fetch | `./fetch.sh` → sparse, shallow checkout of the imgui slice into `vendor/imgui` |

The backend/renderer translation units (`imgui_impl_*`) are intentionally out of
scope: they are what require GL and a windowing system. The core builds headless.

## Upstream build proof (canonical drop-in)

Dear ImGui ships no CMake of its own — the canonical build is to compile its
translation units with a C++ compiler and archive them, which is exactly how
zig-gamedev (and every other consumer) uses it. From `vendor/imgui`:

```sh
c++ -std=c++17 -O2 -I. -c imgui.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp
ar rcs libimgui.a imgui.o imgui_draw.o imgui_tables.o imgui_widgets.o
```

Result — compiles and archives cleanly. Artifact: `libimgui.a` (~1.15 MB).

## Zaza build proof

The slice is expressed in [`build.zig`](build.zig): the four core translation
units as a `zaza.Target.staticLibrary`, plus a headless consumer
([`src/main.cpp`](src/main.cpp)) that creates an ImGui context, builds the font
atlas, runs a few frames of a real widget tree, and reads back the generated
`ImDrawData`.

```sh
zig build          # build the imgui static-library slice + the consumer
zig build run      # build and run the headless consumer
```

Result — builds, and the consumer renders a frame headlessly:

```
zaza+imgui slice: valid=1 cmd_lists=1 vtx=312 idx=504 (font atlas 512x64)
```

`valid=1` with non-zero vertex/index counts means ImGui produced real draw
geometry through the Zaza-built library, with no GPU or windowing backend.

Artifacts:

| Artifact | Path |
|---|---|
| imgui static library (Zaza) | `zig-out/lib/libimgui_Release.a` |
| Headless consumer | `zig-out/bin/imgui_consumer_Release` |
| Zaza package manifest | `zig-out/share/zaza/imgui.json` |

## Comparison

| | Upstream (drop-in) | Zaza |
|---|---|---|
| Build files | none — raw `c++` + `ar` commands | one `build.zig`, one static-library target |
| Compiler | system `c++` (gcc 13.3.0), `-O2` | `zig cc`, ReleaseFast |
| Static library | `libimgui.a` (~1.15 MB) | `libimgui_Release.a` (~4.8 MB) |
| Downstream link + run | not part of the drop-in build | headless consumer builds, links, and runs |

The size difference is a toolchain characteristic (`zig cc` ReleaseFast keeps more
symbols than gcc `-O2` + `ar`); both libraries link and execute correctly.

## Known gaps

- Core only. The `imgui_impl_*` backends and a real glfw/GL sample are out of
  scope; those need `system_sdk` plus GL/X11 dev headers, which is the heavier
  part of the `zig-gamedev` candidate and a natural follow-up slice.
- `imgui_demo.cpp` and the `cimgui.cpp` C wrapper are present in the checkout but
  not part of this slice; the consumer uses the C++ API directly.
- Only the `Release` configuration is proven here.

## Recorded environment

Zig 0.15.2 · gcc 13.3.0 · Dear ImGui 1.87.
