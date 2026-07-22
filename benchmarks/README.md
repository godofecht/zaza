# Benchmarks

One benchmark lives here. It builds a real C++ project with real build systems
and times the real processes. Every number it prints came off a clock on the
machine that printed it.

## Running it

From the repository root:

```bash
zig build --build-file benchmarks/build.zig bench
```

Options go after `--`:

```bash
zig build --build-file benchmarks/build.zig bench -- --reps 9 --units 32
```

| flag | default | meaning |
| --- | --- | --- |
| `--reps N` | 5 | measured repetitions per lane |
| `--warmups N` | 1 | repetitions run first, reported separately, excluded from the statistics |
| `--units N` | 16 | translation units in the generated workload |
| `--workspace PATH` | `benchmarks/.workspace` | where the generated projects go |

The workspace is wiped and regenerated on every run and is gitignored.

Zig 0.14.1 and 0.15.2 both run it. On 0.16.0 the `bench` step fails with a clear
message: the harness drives child processes through `std.process.Child.run`,
which 0.16 removed in favour of an API taking an explicit `Io`. Nothing in
`zig build test` reaches this build file, so the repository's 0.16 support is
unaffected.

## What it measures

The harness generates a synthetic C++17 project: N translation units, a shared
header, and a `main.cpp`, linked into one executable. The same bytes are written
into every lane, so all lanes compile the same code.

Lanes:

| lane | what it is |
| --- | --- |
| `zaza` | `zig build` on a `build.zig` that declares the target through `build_lib/cpp_example.zig`. Uses Zig's bundled clang and libc++. |
| `cmake-sys` | `cmake` + Ninja with the system C++ compiler. |
| `cmake-zigcc` | `cmake` + Ninja with `zig c++` set as `CMAKE_CXX_COMPILER`. |

`cmake-zigcc` exists so that one comparison holds the compiler fixed. Comparing
`zaza` against `cmake-sys` compares two build systems *and* two compilers *and*
two standard libraries, and the clean-build column cannot separate them.

Each repetition, per lane:

1. rewrite the sources to the baseline content
2. delete the build outputs (`.zig-cache` and `zig-out`, or `build/`)
3. **configure**: `cmake -S . -B build -G Ninja`, or `zig build --help`, which
   compiles and runs the build script and enumerates the graph
4. **clean build**: `cmake --build build`, or `zig build`
5. **no-op rebuild**: the same command again with nothing changed
6. change one translation unit
7. **incremental rebuild**: the same command again

Lanes are interleaved inside a repetition so they see the same machine state.

The incremental step edits an integer in one source file. It has to be a real
content change. Zig's cache keys on file contents and Ninja's keys on mtime, so
a bare `touch` would rebuild under one and not the other, and the number would
mean nothing.

## How results are reported

- min, median and max over the measured repetitions, plus the sample count.
  No single figure is presented on its own.
- The warm-up repetition is excluded from the statistics and printed separately,
  labelled as cold-cache.
- Spread is printed as `max/min - 1`. Above 25% the row is flagged `NOISY`.
- Ratios are printed only between lanes that both ran in the same invocation on
  the same machine. A ratio touching a noisy row is marked `?`.
- Machine, OS, CPU, core count and the versions of zig, cmake, ninja and the
  system compiler are printed above the table so a result is attributable.

## What it does not measure

- **Dependency fetching.** Zaza clones dependencies with git; CMake projects use
  FetchContent or a system package manager. Those do different work over a
  network. Timing them would measure a network, not a build system.
- **Memory.** No memory figure is collected, so none is reported.
- **Scaling.** One workload size per run. Pass `--units` and rerun for another
  point. Nothing is extrapolated between points.
- **`examples/cmake_shim`, `examples/cmake_combo`, `examples/cmake_net`.** These
  fetch from the network and drive CMake as a subordinate step of a Zig build.
  There is no CMake-only equivalent doing the same work, so there is no fair
  race to run.
- **Anything about zaza's C++-only path against a CMake project using a
  different generator, different flags, or LTO.** Only what is listed above ran.

## Why the previous files were deleted

Four files used to sit in this directory: `performance_benchmark.zig`,
`memory_benchmark.zig`, `scalability_benchmark.zig` and `cmake_comparison.zig`.
They are in the git history. Do not resurrect them.

They did not benchmark anything. They computed results from hardcoded constants
and printed them as measurements. A representative example:

```zig
fn benchmarkZazaIncremental(allocator, project_size, change_percentage) !IncrementalResult {
    // Simulate Zaza incremental build performance
    const base_time = 100.0;
    const incremental_time = base_time * change_percentage * 0.1;
    const speedup_factor = base_time / incremental_time;
```

Nothing is built. Nothing is timed. `project_size` is unused. There were 17
comments beginning "Simulate" across the four files, including a "Simulated
CMake baseline" against which zaza was declared several times faster. The old
`benchmarks/README.md` reported those invented figures as findings: "2-5x faster
build times", "60-80% less memory usage", specific megabyte numbers for project
sizes that were never built.

The files failed to compile on 0.14.1, 0.15.2 and 0.16.0, which is the only
reason those numbers were never published from a run.

The current harness prints a comparison ratio only when both sides were measured
in the same run, and prints nothing at all for quantities it did not measure.
