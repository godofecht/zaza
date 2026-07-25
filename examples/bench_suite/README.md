# bench_suite

A benchmark target declared through Zaza's first-class benchmark API,
`test_suite.addBench`. It exists to show the API, so the workload is a trivial
compute loop rather than a real measurement.

```sh
zig build bench-suite-run
zig build bench-suite-run -- --reps 9
```

`addBench` builds in release, keeps the target off `zig build test`, inherits
stdio so the timings print, and forwards the `-- --reps N` argument to the
process. See [`docs/WIKI.md`](../../docs/WIKI.md#testing-and-benchmarks) for the
API and the difference from `addTest`.
