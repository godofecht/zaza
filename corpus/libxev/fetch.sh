#!/bin/sh
# Fetch libxev at a pinned commit and build its C static library, then stage the
# library and header into vendor/libxev. Requires Zig 0.16 on PATH (libxev's
# minimum_zig_version). Vendor output is git-ignored. Re-running is safe.
set -eu

LIBXEV_COMMIT=9ce8e8e6ff89e583258a7f8e7adeeeaeae8611bf
DIR=$(cd "$(dirname "$0")" && pwd)
VENDOR="$DIR/vendor/libxev"

if [ -f "$VENDOR/libxev.a" ] && [ -f "$VENDOR/xev.h" ]; then
    echo "libxev already staged at $VENDOR"
    exit 0
fi

SRC="$DIR/vendor/_libxev-src"
rm -rf "$SRC"
mkdir -p "$DIR/vendor"
echo "fetching libxev @ $LIBXEV_COMMIT ..."
git clone --filter=blob:none https://github.com/mitchellh/libxev "$SRC"
git -C "$SRC" checkout -q "$LIBXEV_COMMIT"
echo "building libxev C static library (needs Zig 0.16) ..."
( cd "$SRC" && zig build -Doptimize=ReleaseFast )
mkdir -p "$VENDOR"
cp "$SRC/zig-out/lib/libxev.a" "$VENDOR/libxev.a"
cp "$SRC/include/xev.h" "$VENDOR/xev.h"
rm -rf "$SRC"
echo "libxev staged at $VENDOR"
