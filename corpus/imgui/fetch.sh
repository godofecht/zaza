#!/bin/sh
# Fetch the Dear ImGui core sources vendored in zig-gamedev into vendor/imgui.
# A sparse, shallow checkout keeps this to the imgui slice rather than the whole
# zig-gamedev monorepo. Vendor sources are git-ignored; only this script and the
# Zaza build files are committed. Re-running is safe.
set -eu

# Pinned zig-gamedev commit; the vendored Dear ImGui is version 1.87.
GAMEDEV_COMMIT=9af37ec05bbfe5164dafc4c741a7d35667bd09c5
SLICE=samples/common/libs/imgui
DIR=$(cd "$(dirname "$0")" && pwd)
VENDOR="$DIR/vendor/imgui"

if [ -f "$VENDOR/imgui.h" ]; then
    echo "imgui slice already present at $VENDOR"
    exit 0
fi

TMP="$DIR/vendor/_zig-gamedev"
rm -rf "$TMP"
mkdir -p "$DIR/vendor"
echo "fetching zig-gamedev @ $GAMEDEV_COMMIT (sparse: $SLICE) ..."
git clone --depth 1 --filter=blob:none --sparse https://github.com/zig-gamedev/zig-gamedev "$TMP"
git -C "$TMP" sparse-checkout set "$SLICE"
git -C "$TMP" fetch --depth 1 origin "$GAMEDEV_COMMIT"
git -C "$TMP" checkout -q "$GAMEDEV_COMMIT"
cp -r "$TMP/$SLICE" "$VENDOR"
rm -rf "$TMP"
echo "imgui slice checked out at $VENDOR"
