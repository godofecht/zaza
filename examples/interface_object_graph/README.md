# Interface / Object / Static Graph

An object library folded into a static library, consumed by an executable, with shared usage flags.

## What it demonstrates

- `b.addObject` output linked into a static library.
- A shared flag set (`-DGRAPH_API_LEVEL=4`) applied across the whole graph.
- Three-level target composition in one build file.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=interface-object-graph zig build interface-object-graph      # build only
ZAZA_EXAMPLES=interface-object-graph zig build interface-object-graph-run  # build and run
```

## Expected output

```text
graph result: 42
graph api level: 4
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
