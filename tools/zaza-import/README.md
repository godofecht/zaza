# zaza-import

Generate a starter Zaza `build.zig` from a CMake project's
`compile_commands.json` (zaza#43).

CMake emits `compile_commands.json` when configured with
`-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`. That file records the exact compiler
invocation for every translation unit. `zaza-import` reads it and extracts the
include directories (`-I`), preprocessor defines (`-D`), language standard
(`-std=`), and source files, then writes them as a Zaza target.

```sh
zig build zaza-import          # installs zig-out/bin/zaza-import
zaza-import compile_commands.json --name my_app --kind exe --out build.zig
```

Flags: `--name` (target name), `--kind exe|static|shared`, `--out` (output path,
default `build.zig.generated`).

## What it does and doesn't do

It imports the *compile* side faithfully. It is a starting point, not a finished
build, and says so — anything it can't infer becomes an explicit TODO rather than
a silent omission:

- `compile_commands.json` has **no target graph**, so every translation unit is
  merged into one target. Split into per-library targets and wire link
  dependencies + usage requirements (public/private) by hand.
- **System/link libraries and install rules** aren't in `compile_commands.json`;
  add `public_link_libs` / `install_*` as needed.
- Unmapped compile flags (`-O`, `-W`, `-f`, `-g`) are listed as a TODO so you can
  promote the ones that matter to `cpp_flags`.

This is the import direction; Zaza also *exports* a `CMakeLists.txt` and
*consumes* CMake projects (see `examples/cmake*`).
