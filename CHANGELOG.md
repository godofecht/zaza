# Changelog

## Unreleased
- Added an external corpus under `corpus/`: real upstream repos rebuilt through
  Zaza and compared against their native build. First slice: `fmt` (static
  library + linked consumer, with a CMake upstream proof). See `corpus/README.md`.
- Manifest dependencies are now lazy, so a build fetches only the packages its
  targets actually consume instead of eagerly pulling the whole dependency set.

## v0.2.0 - 2026-02-10
- Added `cmake-net` example (curl + zlib + mbedtls) with build/run steps.
- Added `cmake-combo-run` and `cmake-net-run` steps with banner output.
- Improved `run-cpp` UX with banner, info block, and flag passthrough.
- Added roadmap documentation.
