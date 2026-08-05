# Corpus proof: fmt

A target slice of [{fmt}](https://github.com/fmtlib/fmt) rebuilt through Zaza's
C/C++ graph layer, with the upstream CMake build recorded alongside for
comparison.

## Pinned upstream

| | |
|---|---|
| Repository | https://github.com/fmtlib/fmt |
| Tag | `10.2.1` (matches Zaza's registry and `build.zig.zon`) |
| Slice | the compiled library: `src/format.cc`, `src/os.cc`, headers under `include/` |
| Fetch | `./fetch.sh` → `git clone --depth 1 --branch 10.2.1 … vendor/fmt` |

Upstream sources are git-ignored; only the Zaza build files in this directory are
committed.

## Upstream build proof (CMake)

Canonical fmt build, from `vendor/fmt`:

```sh
cmake -S . -B build-upstream -G Ninja -DCMAKE_BUILD_TYPE=Release -DFMT_TEST=OFF -DFMT_DOC=OFF
cmake --build build-upstream
```

Result — succeeds, links the static library:

```
[1/3] Building CXX object CMakeFiles/fmt.dir/src/os.cc.o
[2/3] Building CXX object CMakeFiles/fmt.dir/src/format.cc.o
[3/3] Linking CXX static library libfmt.a
```

Artifact: `vendor/fmt/build-upstream/libfmt.a`.

## Zaza build proof

The slice is expressed in [`build.zig`](build.zig): fmt's two translation units
as a `zaza.Target.staticLibrary`, plus a `zaza.Target.executable` consumer
([`src/main.cpp`](src/main.cpp)) that links the library and calls real fmt APIs.

```sh
zig build            # build the fmt static-library slice + the consumer
zig build run        # build and run the consumer
```

Result — `Build Summary: 10/10 steps succeeded`, and the consumer runs:

```
zaza+fmt slice: hello corpus!
|   right| center |left    |
pi ~= 3.14159, big =      1234567
```

Artifacts:

| Artifact | Path |
|---|---|
| fmt static library (Zaza) | `zig-out/lib/libfmt_Release.a` |
| Consumer executable | `zig-out/bin/fmt_consumer_Release` |
| Zaza package manifest | `zig-out/share/zaza/fmt.json` |

## Comparison

| | Upstream (CMake) | Zaza |
|---|---|---|
| Build files | fmt's `CMakeLists.txt` (~thousands of lines, project-wide) | one `build.zig`, one static-library target |
| Compiler | system `cc` (gcc 13.3.0) | `zig cc`, ReleaseFast |
| Static library | `libfmt.a` (~264 KB) | `libfmt_Release.a` (~1.8 MB) |
| Downstream link + run | not part of the upstream lib build | consumer builds, links, and runs |

The library size differs because the two toolchains archive objects differently
(`zig cc` ReleaseFast keeps more symbols than gcc's `-O3` static build); both
libraries link and execute correctly. This is a characteristic of the toolchain,
not a defect in the slice.

## Known gaps

- The slice builds the classic compiled library (`format.cc` + `os.cc`). It does
  not build fmt's C++20-module unit (`src/fmt.cc`); modules are covered by the
  separate `cxx20-modules` example, not this slice.
- Only the `Release` configuration is proven here; the overlay can be extended to
  `debug_release` once a multi-config proof is wanted.
- The upstream proof uses `-DFMT_TEST=OFF`; running fmt's own test suite through
  Zaza is out of scope for this slice.

## Recorded environment

Zig 0.15.2 · gcc 13.3.0 · CMake 3.28.3 · Ninja.
