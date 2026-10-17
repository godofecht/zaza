#!/bin/sh
set -eu

src="$1"
out="$2"
mkdir -p "$(dirname "$out")"
cp "$src" "$out"
