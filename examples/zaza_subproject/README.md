# Zaza Subproject

A Zaza subproject with its own `build.zig`, composed into a parent Zaza build.

## What it demonstrates

- The zaza-to-zaza `add_subdirectory` path: `libs/greet` keeps its own
  `build.zig` and builds its own `greet` static library.
- `defineSubproject` in the subproject, exposing that library by name.
- `Subproject.linkInto` in the parent, linking the library and its headers in
  one build graph.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=zaza-subproject zig build zaza-subproject      # build only
ZAZA_EXAMPLES=zaza-subproject zig build zaza-subproject-run  # build and run
```

## Expected output

```text
zaza top-level linked a zaza subproject: greet: parent linked a zaza subproject library
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
