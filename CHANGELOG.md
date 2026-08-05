# Changelog

## Unreleased
- Added an external corpus under `corpus/`: real upstream repos rebuilt through
  Zaza and compared against their native build. Slices: `fmt` and `imgui` (Dear
  ImGui core from zig-gamedev), each a static library + a linked consumer with an
  upstream build proof. See `corpus/README.md`.
- Recorded corpus findings for `libxev` (C API only compiles as C99; `zaza.Target`
  needs a C-language option to consume it) and `libvaxis` (pure Zig, no C/C++
  surface), plus an assessment of `szkkng/juzi` vs Zaza's JUCE support.
- Manifest dependencies are now lazy, so a build fetches only the packages its
  targets actually consume instead of eagerly pulling the whole dependency set.

## v0.2.0 - 2026-02-10
- Added `cmake-net` example (curl + zlib + mbedtls) with build/run steps.
- Added `cmake-combo-run` and `cmake-net-run` steps with banner output.
- Improved `run-cpp` UX with banner, info block, and flag passthrough.
- Added roadmap documentation.
