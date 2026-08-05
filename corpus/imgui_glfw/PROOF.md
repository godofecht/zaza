# Corpus proof: imgui + GLFW/OpenGL3 backends

A target slice that extends the [`imgui`](../imgui) core slice with a real
windowing and rendering backend: [Dear ImGui](https://github.com/ocornut/imgui)
core plus its `imgui_impl_glfw` and `imgui_impl_opengl3` backends, linked against
system **GLFW** and **OpenGL**. This is the heavier end of the corpus issue's
`zig-gamedev` candidate — the glfw + imgui + GL dependency graph — rather than the
system-free core.

## Pinned upstream

| | |
|---|---|
| Repository | https://github.com/ocornut/imgui |
| Commit | `c71a50deb5ddf1ea386b91e60fa2e4a26d080074` (**v1.87**, same core version as the `imgui` slice) |
| Slice | core (`imgui.cpp`, `imgui_draw.cpp`, `imgui_tables.cpp`, `imgui_widgets.cpp`) + `backends/imgui_impl_glfw.cpp` + `backends/imgui_impl_opengl3.cpp` |
| Fetch | `./fetch.sh` → checks the pinned imgui release out into `vendor/imgui` |

## System prerequisites

Unlike `fmt`, `imgui`, and `libxev`, this slice needs platform GL/GLFW libraries
at build time and a GL-capable display at run time:

```sh
# Debian/Ubuntu
apt-get install libglfw3-dev libgl1-mesa-dev libgl1-mesa-dri xvfb
```

## Upstream build proof (canonical drop-in)

Dear ImGui and its backends are drop-in translation units. From `vendor/imgui`:

```sh
g++ -std=c++17 -O2 -I. -I backends -c \
    imgui.cpp imgui_draw.cpp imgui_tables.cpp imgui_widgets.cpp \
    backends/imgui_impl_glfw.cpp backends/imgui_impl_opengl3.cpp
ar rcs libimgui_glfw.a imgui.o imgui_draw.o imgui_tables.o imgui_widgets.o \
    imgui_impl_glfw.o imgui_impl_opengl3.o
```

Result — compiles and archives cleanly. Artifact: `libimgui_glfw.a` (~1.2 MB).

## Zaza build proof

The slice is expressed in [`build.zig`](build.zig): the six translation units as
a `zaza.Target.staticLibrary`, plus a consumer ([`src/main.cpp`](src/main.cpp))
that opens a GLFW window, creates an OpenGL context, initialises both ImGui
backends, and renders a real frame through `ImGui_ImplOpenGL3_RenderDrawData`.
The consumer links system `glfw` and `GL` via `public_link_libs`.

It runs headless under a virtual framebuffer with Mesa's software GL:

```sh
./fetch.sh
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a zig build run
```

Result — builds, and the consumer renders a frame against a real GL context:

```
zaza+imgui+glfw slice: GL=4.5 (Core Profile) Mesa 25.2.8 | valid=1 vtx=242 idx=411
```

`valid=1` with non-zero geometry, reported alongside the live `GL_VERSION` string,
means the frame went through GLFW window creation, a GL context, and both ImGui
backends — not just the core.

Artifacts:

| Artifact | Path |
|---|---|
| imgui+backends static library (Zaza) | `zig-out/lib/libimgui_glfw_Release.a` |
| Consumer executable | `zig-out/bin/imgui_glfw_consumer_Release` |
| Zaza package manifest | `zig-out/share/zaza/imgui_glfw.json` |

## Comparison

| | Upstream (drop-in) | Zaza |
|---|---|---|
| Build files | raw `g++` + `ar` commands | one `build.zig`, one static-library target + a consumer |
| System libraries | linked by hand (`pkg-config --libs glfw3 gl`) | declared via `public_link_libs = &.{ "glfw", "GL" }` |
| Static library | `libimgui_glfw.a` (~1.2 MB) | `libimgui_glfw_Release.a` (~5.0 MB) |
| Windowed render | run by hand under Xvfb | consumer builds, links, and renders under Xvfb |

## Known gaps

- Headless run uses Mesa's `llvmpipe` software rasteriser under Xvfb; there is no
  GPU in scope. The GL path is exercised, but not a hardware driver.
- One backend pair (`glfw` + `opengl3`). Other backends (`sdl`, `vulkan`, `dx*`)
  are out of scope.
- Only the `Release` configuration is proven here.

## Recorded environment

Zig 0.15.2 · gcc 13.3.0 · GLFW 3.3.10 · Mesa 25.2.8 (llvmpipe) · Dear ImGui 1.87 · Xvfb.
