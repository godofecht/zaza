#!/bin/sh
# Verify the "consumed by CMake" direction end to end:
#   1. Zaza builds and installs package_math as a CMake package (imported target
#      + Config.cmake + ConfigVersion.cmake) into a prefix.
#   2. A plain CMake project finds it with find_package and links it.
#   3. The resulting binary runs and returns success.
#
# Usage: ZIG=/path/to/zig sh examples/cmake_consumer/verify.sh
# Run from the zaza repo root. Native toolchains only; no arch override, so the
# Zig-built library and the CMake compiler must target the same architecture.
set -eu

ZIG="${ZIG:-zig}"
ROOT="$(pwd)"
PREFIX="$ROOT/zig-out"
BUILD_DIR="${BUILD_DIR:-/tmp/zaza-cmake-consumer-build}"

echo "[1/3] building + installing the Zaza CMake package (package_math)"
rm -rf "$PREFIX"
ZAZA_EXAMPLES=package-producer "$ZIG" build

test -f "$PREFIX/lib/cmake/package_math/package_mathConfig.cmake" \
    || { echo "FAIL: package_mathConfig.cmake not installed"; exit 1; }

echo "[2/3] configuring + building the downstream CMake consumer"
rm -rf "$BUILD_DIR"
cmake -S examples/cmake_consumer -B "$BUILD_DIR" -DCMAKE_PREFIX_PATH="$PREFIX"
cmake --build "$BUILD_DIR"

echo "[3/3] running the consumer"
"$BUILD_DIR/cmake_consumer"
echo "OK: a CMake project consumed a Zaza-built library via find_package"
