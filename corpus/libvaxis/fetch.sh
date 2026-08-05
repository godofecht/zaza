#!/bin/sh
# Pre-seed the Zig package cache with libvaxis and its dependencies at their
# pinned commits, so `zig build` resolves them without network access.
#
# In a normal networked environment this is unnecessary — `zig build` fetches
# the git dependencies declared in build.zig.zon itself. It is needed only where
# Zig's package fetcher cannot reach GitHub directly (e.g. a proxied sandbox),
# because git-over-https via a proxy still works through the git CLI used here.
#
# Requires Zig 0.16 on PATH (libvaxis's minimum_zig_version).
set -eu

VAXIS=5ca495f09f413c66789d9c5061359b941a8d82c2
ZIGIMG=d695acd97c02e57bb151e8f659d1280f5cd6ca70
UUCODE=2826a37a4562284fdacd8fa029d49509cc9bffcd

seed() { # url commit
    d=$(mktemp -d)
    git clone --quiet --filter=blob:none "$1" "$d"
    git -C "$d" checkout --quiet "$2"
    zig fetch "$d"        # computes the package hash and stores it in the cache
    rm -rf "$d"
}

# Leaf dependencies first, then libvaxis (its fetch resolves them from cache).
echo "seeding zigimg ..."; seed https://github.com/zigimg/zigimg "$ZIGIMG"
echo "seeding uucode ..."; seed https://github.com/jacobsandlund/uucode "$UUCODE"
echo "seeding libvaxis ..."; seed https://github.com/rockorager/libvaxis "$VAXIS"
echo "cache seeded; now run: zig build run"
