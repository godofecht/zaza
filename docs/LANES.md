# Zig lanes

Zaza is maintained and CI-tested against a fixed set of Zig versions ("lanes").
Sources and build files use spellings valid on all of them, falling back to
`if (comptime @hasDecl(...))` where no shared spelling exists (the `std.Io`
filesystem move, `ArrayList` going unmanaged, Compile add*/link* forwarders,
`std.json`'s unmanaged `ObjectMap`).

## Supported lanes

| Lane | Zig version |
|------|-------------|
| 0.14 | `0.14.1` |
| 0.15 | `0.15.2` |
| 0.16 | `0.16.0` |

These are exposed as data for downstream projects:

```zig
const zaza = @import("zaza").api;
// zaza.supported_lanes : []const std.SemanticVersion
// zaza.laneSupported(builtin.zig_version) : bool
```

`build.zig` checks the running Zig against this list and prints a clear warning
when it is outside the validated lanes, so a mismatch is reported up front rather
than surfacing as a confusing build error.

## Pinning a lane

Pin the Zig version in your toolchain (`.zigversion`, `mise`, `asdf`,
`mlugg/setup-zig`, etc.) to one of the supported patch versions above. Zaza does
not download a toolchain for you; it validates the one you run.

## Per-lane cache isolation

Zig's local build cache is not keyed by compiler version, so building the same
tree with two different lanes can cross-contaminate a stale cache. Isolate it by
lane with a per-lane local cache directory:

```sh
ZIG_LOCAL_CACHE_DIR=.zig-cache-0.16.0 zig build
```

CI does this automatically — each matrix lane sets
`ZIG_LOCAL_CACHE_DIR=.zig-cache-<version>`, so the three lanes never share a
cache. Mirror that in downstream CI when you build on more than one lane.
