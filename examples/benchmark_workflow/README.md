# Benchmark Workflow

A benchmark executable exposed as two run targets that differ only by workload size.

## What it demonstrates

- Modelling a benchmark as a first-class build target rather than a script.
- Two run targets over one artifact, separated by a command-line argument.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=benchmark-workflow zig build benchmark-workflow        # build only
ZAZA_EXAMPLES=benchmark-workflow zig build benchmark-workflow-run    # 750000 iterations
ZAZA_EXAMPLES=benchmark-workflow zig build benchmark-workflow-quick  # 100000 iterations
```

## Expected output

```text
benchmark iterations: 750000
benchmark checksum: 4761326831600
benchmark elapsed_us: 2536
```

## Notes

`elapsed_us` varies between runs. The checksum does not.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
