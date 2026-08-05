#!/bin/sh
# Reproduces the Zaza-toolchain build proof for the libxev C consumer: compile
# src/main.c with `zig cc` (the compiler Zaza wraps) as C99, link libxev's C
# static library, and run it. Run ./fetch.sh first. `zig` here may be 0.15 or
# 0.16 for the consumer; libxev.a itself was built by 0.16 in fetch.sh.
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
VENDOR="$DIR/vendor/libxev"
[ -f "$VENDOR/libxev.a" ] || { echo "run ./fetch.sh first"; exit 1; }

zig cc -std=c99 -D_POSIX_C_SOURCE=199309L \
    -I "$VENDOR" "$DIR/src/main.c" "$VENDOR/libxev.a" \
    -o "$DIR/libxev_consumer"
"$DIR/libxev_consumer"
