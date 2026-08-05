# Changelog

## Unreleased
- Added a `c_std` option to `zaza.Target`: build a target as C (`-std=c<std>`,
  no RTTI/exceptions, links `libc`) instead of C++. This unblocks C-only libraries
  and headers that do not compile as C++. Honoured in the Zig compile, the
  zaza-drive manifest, and the `export_cmake` CMakeLists output.
- Added an external corpus under `corpus/`: real upstream repos rebuilt through
  Zaza and compared against their native build. Validated slices: `fmt`, `imgui`
  (Dear ImGui core from zig-gamedev), `imgui_glfw` (Dear ImGui with the GLFW +
  OpenGL3 backends, linked against system GLFW/GL and run headless under Xvfb), and
  `libxev` (C API consumer via `c_std`) — each with an upstream build proof and a
  Zaza build proof. See `corpus/README.md`.
- Recorded a corpus finding for `libvaxis` (pure Zig, no C/C++ surface) and an
  assessment of `szkkng/juzi` vs Zaza's JUCE support.
- Manifest dependencies are now lazy, so a build fetches only the packages its
  targets actually consume instead of eagerly pulling the whole dependency set.

## v0.2.0 - 2026-02-10
- Added `cmake-net` example (curl + zlib + mbedtls) with build/run steps.
- Added `cmake-combo-run` and `cmake-net-run` steps with banner output.
- Improved `run-cpp` UX with banner, info block, and flag passthrough.
- Added roadmap documentation.
