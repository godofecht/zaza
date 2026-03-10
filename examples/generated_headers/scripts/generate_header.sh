#!/bin/sh
set -eu

out="$1"
mkdir -p "$(dirname "$out")"
cat > "$out" <<'EOF'
#pragma once

inline const char* generated_header_message() {
    return "generated header is working";
}
EOF
