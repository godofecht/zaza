#!/bin/sh
# Fetch Dear ImGui (core + GLFW/OpenGL3 backends) at a pinned release into
# vendor/imgui. Vendor sources are git-ignored; only this script and the Zaza
# build files are committed. Re-running is safe.
#
# This slice also needs system GLFW and OpenGL development libraries at build
# time and a GL-capable display at run time:
#   Debian/Ubuntu: apt-get install libglfw3-dev libgl1-mesa-dev libgl1-mesa-dri
#   headless run:   apt-get install xvfb   (then: xvfb-run -a zig build run)
set -eu

IMGUI_COMMIT=c71a50deb5ddf1ea386b91e60fa2e4a26d080074   # v1.87
DIR=$(cd "$(dirname "$0")" && pwd)
VENDOR="$DIR/vendor/imgui"

if [ -f "$VENDOR/backends/imgui_impl_glfw.cpp" ]; then
    echo "imgui (with backends) already present at $VENDOR"
    exit 0
fi

rm -rf "$VENDOR"
mkdir -p "$DIR/vendor"
echo "fetching Dear ImGui @ $IMGUI_COMMIT (v1.87) ..."
git clone --filter=blob:none https://github.com/ocornut/imgui "$VENDOR"
git -C "$VENDOR" checkout -q "$IMGUI_COMMIT"
echo "imgui checked out at $VENDOR"
