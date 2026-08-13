# Orchestration

Three build-orchestration features in one target: a generator-expressioned
define, a target-level linker option, and a phony orchestration target.

## What it demonstrates

- **Generator expressions.** `BUILD_MODE=$<IF:$<CONFIG:Debug>,debug,release>` is
  evaluated against the active config, so the compiled program prints the
  config-specific value.
- **`target_link_options`.** `link_options = &.{.{ .gc_sections = true }}` drops
  unreferenced sections at link time.
- **`add_custom_target`.** `zaza.addPhonyTarget` creates `orchestration-run`, a
  named step that builds the executable and runs it.

## Prerequisites

Zig 0.14.1, 0.15.2 or 0.16.0. Nothing else.

## Build and run

```bash
ZAZA_EXAMPLES=orchestration zig build orchestration      # build only
ZAZA_EXAMPLES=orchestration zig build orchestration-run  # build and run (phony target)
```

## Expected output

```text
orchestration demo: generator-expressioned BUILD_MODE = debug
```

Built in the Debug config, so the generator expression resolves to `debug`. A
Release config resolves the same define to `release`.

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
