#!/usr/bin/env bash
#
# Reproducible race: zaza-drive against Ninja and `zig build`, same workload,
# same machine, same compiler (zig c++ for all three, so the comparison is
# build-system only). Prints min/median/max for no-op and incremental.
#
# Usage:  ./bench.sh [units] [reps]
# Needs:  zig, cmake, ninja, python3 on PATH.
set -euo pipefail
cd "$(dirname "$0")"

ZIG="${ZIG:-zig}"
UNITS="${1:-16}"
REPS="${2:-6}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> workload: $UNITS translation units + main, in $WORK"
mkdir -p "$WORK/src" "$WORK/include"
cat > "$WORK/include/shared.hpp" <<'H'
#pragma once
inline int ver() { return 1; }
H
for i in $(seq 0 $((UNITS - 1))); do
  cat > "$WORK/src/unit_$i.cpp" <<U
#include "shared.hpp"
static unsigned h$i(unsigned x){ unsigned a=x; for(int k=0;k<40;k++) a=a*2u+k+$i; return a; }
unsigned unit_$i(unsigned x){ return h$i(x) + ver() - $i; }
U
done
{
  for i in $(seq 0 $((UNITS - 1))); do echo "unsigned unit_$i(unsigned);"; done
  echo "int main(int c, char**){ unsigned s=0;"
  for i in $(seq 0 $((UNITS - 1))); do echo "  s += unit_$i((unsigned)c);"; done
  echo "  return (int)(s & 0x7f); }"
} > "$WORK/src/main.cpp"

# --- lane: zig build ---------------------------------------------------------
Z="$WORK/zbuild"; mkdir -p "$Z"; cp -r "$WORK/src" "$WORK/include" "$Z/"
{
  echo 'const std = @import("std");'
  echo 'pub fn build(b: *std.Build) void {'
  echo '  const t = b.standardTargetOptions(.{}); const o = b.standardOptimizeOption(.{});'
  echo '  const e = b.addExecutable(.{ .name = "app", .root_module = b.createModule(.{ .target = t, .optimize = o, .root_source_file = null }) });'
  printf '  var f: [%d][]const u8 = undefined; f[0] = "src/main.cpp";\n' "$((UNITS + 1))"
  printf '  for (0..%d) |i| f[i+1] = b.fmt("src/unit_{d}.cpp", .{i});\n' "$UNITS"
  echo '  e.root_module.addCSourceFiles(.{ .files = &f, .flags = &.{"-std=c++17","-g"} });'
  echo '  e.root_module.addIncludePath(b.path("include")); e.root_module.link_libcpp = true;'
  echo '  b.installArtifact(e); }'
} > "$Z/build.zig"

# --- lane: cmake + ninja (zig c++ as the compiler) ---------------------------
N="$WORK/ninja"; mkdir -p "$N"; cp -r "$WORK/src" "$WORK/include" "$N/"
cat > "$N/CMakeLists.txt" <<C
cmake_minimum_required(VERSION 3.20)
project(app CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_BUILD_TYPE Debug)
file(GLOB S src/*.cpp)
add_executable(app \${S})
target_include_directories(app PRIVATE include)
C
cmake -G Ninja -B "$N/build" -S "$N" -DCMAKE_CXX_COMPILER="$(command -v "$ZIG")" \
      -DCMAKE_CXX_COMPILER_ARG1=c++ >/dev/null 2>&1

# --- lane: zaza-drive --------------------------------------------------------
D="$WORK/drive"; mkdir -p "$D"; cp -r "$WORK/src" "$WORK/include" "$D/"
"$ZIG" build-exe main.zig -O ReleaseFast -femit-bin="$D/zaza-drive" >/dev/null 2>&1
{
  echo "compiler $(command -v "$ZIG") c++"
  echo "cflags -std=c++17 -g -Iinclude"
  echo "outdir .zaza-drive"
  echo "bin app"
  for i in $(seq 0 $((UNITS - 1))); do echo "src src/unit_$i.cpp"; done
  echo "src src/main.cpp"
} > "$D/build.manifest"

python3 - "$ZIG" "$Z" "$N" "$D" "$REPS" <<'PY'
import subprocess, time, statistics, os, sys, shutil, re
zig, Z, N, D, reps = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
def t1(cmd, cwd): t=time.monotonic(); subprocess.run(cmd, cwd=cwd, capture_output=True); return (time.monotonic()-t)*1000
def stats(fn): xs=[fn() for _ in range(reps)]; return min(xs), statistics.median(xs), max(xs)
def touch(cwd):
    p=os.path.join(cwd,"src/unit_3.cpp"); s=open(p).read()
    m=re.search(r'\+ k \+ (\d+)', s)
    open(p,"w").write(s[:m.start()]+f"+ k + {int(m.group(1))+1}"+s[m.end():] if m else s+"\n//x\n")
lanes = {
    "zaza-drive": (D, ["./zaza-drive","build.manifest"]),
    "ninja":      (os.path.join(N,"build"), ["ninja"]),
    "zig build":  (Z, [zig,"build"]),
}
for _,(cwd,cmd) in lanes.items(): subprocess.run(cmd, cwd=cwd, capture_output=True)  # warm
print(f"\n  {'phase':<13}{'lane':<12}{'min':>8}{'median':>9}{'max':>8}  ms")
print("  " + "-"*50)
for name,(cwd,cmd) in lanes.items():
    mn,md,mx = stats(lambda: t1(cmd, cwd))
    print(f"  {'no-op':<13}{name:<12}{mn:8.1f}{md:9.1f}{mx:8.1f}")
print()
for name,(cwd,cmd) in lanes.items():
    tcwd = N if name=="ninja" else (Z if name=="zig build" else D)
    def one():
        subprocess.run(cmd, cwd=cwd, capture_output=True)
        touch(tcwd)
        return t1(cmd, cwd)
    mn,md,mx = stats(one)
    print(f"  {'incremental':<13}{name:<12}{mn:8.1f}{md:9.1f}{mx:8.1f}")
PY
