# Dependencies: fetch, cache, and reproducibility

Zaza keeps external dependencies boring and reproducible. There are four kinds,
handled separately.

## The four kinds

| Kind | Where it lives | How it's pinned |
|------|----------------|-----------------|
| **Zig package deps** | `build.zig.zon` `.dependencies` | url + hash (Zig's own lock) |
| **Registry / CMake deps** (fmt, spdlog, curl, JUCE, …) | fetched into `build.zig.zon` on first build | url + hash, via `scripts/zaza.zig fetch <name>` |
| **Vendored deps** (corpus slices) | git-ignored `vendor/`, staged by a slice's `fetch.sh` | pinned upstream commit in `fetch.sh` |
| **System deps** | the host | not fetched; discovered at link time |

Each kind is pinned to an exact source, so a build is a function of the committed
files plus the host toolchain.

## Reproducible from a fresh clone

Once a dependency is pinned in `build.zig.zon` (url + hash), it resolves from the
Zig package cache deterministically — the same bytes on every machine. The first
build of a fresh clone fetches any not-yet-pinned registry dep and writes its
url + hash into `build.zig.zon`; commit that, and every later clone is
reproducible with no further fetch.

## Offline / cache-validation mode

Set `ZAZA_OFFLINE=1` to forbid any network fetch. A dependency that is not
already pinned then fails with a message naming the **package**, its **source**,
and the **remediation** — instead of a raw fetcher error. Use it to validate that
a checkout is fully vendored and will build with no network:

```sh
ZAZA_OFFLINE=1 zig build            # fails clearly if anything isn't pinned
```

Auto-fetch of registry deps can also be turned off entirely with `ZAZA_REGISTRY=0`.

## Dependency failure messages

A missing or unresolved dependency reports the package, the source it would come
from, and how to fix it, rather than surfacing a bare fetch failure. The corpus
slices additionally ship a `fetch.sh` that pins and seeds the cache so they build
in a proxied or offline sandbox (see `corpus/*/PROOF.md`).
