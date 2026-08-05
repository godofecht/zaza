#!/bin/sh
# Fetch the pinned upstream fmt release into vendor/fmt for the corpus overlay.
# Vendor sources are git-ignored; only this script and the Zaza build files are
# committed. Re-running is safe.
set -eu

FMT_TAG=10.2.1
DIR=$(cd "$(dirname "$0")" && pwd)
VENDOR="$DIR/vendor/fmt"

if [ -f "$VENDOR/include/fmt/core.h" ]; then
    echo "fmt $FMT_TAG already present at $VENDOR"
    exit 0
fi

mkdir -p "$DIR/vendor"
echo "fetching fmt $FMT_TAG ..."
git clone --depth 1 --branch "$FMT_TAG" https://github.com/fmtlib/fmt "$VENDOR"
echo "fmt $FMT_TAG checked out at $VENDOR"
