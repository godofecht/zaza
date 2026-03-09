#!/bin/sh
set -eu

out="$1"
mkdir -p "$(dirname "$out")"
cat > "$out" <<'EOF'
#include <string>

const char* generated_message() {
    return "generated code is working";
}
EOF
