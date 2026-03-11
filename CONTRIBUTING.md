# Contributing

## Scope

Vex is trying to prove a serious replacement path for new CMake-based native
projects. Contributions should improve one of these:

- target graph capability
- packaging and downstream consumption
- generated code or custom-command workflows
- CMake interop
- WebAssembly workflows
- documentation quality
- verified example coverage

## Development Setup

Prerequisites:

- Zig 0.14.0 or newer
- Git
- Python 3 for web demo smoke paths
- optional: `direnv`

Basic setup:

```bash
git clone <repo-url>
cd <repo-dir>
direnv allow
zig build test
zig build example-matrix
```

If you are working on targets that need external system tools, enable them
explicitly:

```bash
VEX_SYSTEM_CMDS=1 zig build cmake-shim
```

## Change Expectations

- keep changes scoped to one problem or one example stage
- do not mix cache churn or generated junk into commits
- keep target names explicit and grep-friendly
- prefer verified behavior over aspirational docs
- update docs when command names or workflows change

## Validation

Minimum bar for most changes:

```bash
zig build test
zig build example-matrix
```

If your change only affects a subset of the graph, also run the most relevant
target directly and mention it in the commit or PR description.

Examples:

```bash
zig build package-consumer-run
zig build shared-plugin-run
zig build wasm-web-demo-smoke
```

## Docs

If you add or rename an example, update the relevant docs:

- `README.md`
- `docs/EXAMPLES.md`
- `docs/SYNTAX_REFERENCE.md`
- `docs/ROADMAP.md` when roadmap status changes

## Pull Requests

A good PR should make it obvious:

- what changed
- why it changed
- which commands were used to verify it
- whether any environment-specific limitation still exists

Small, reviewable PRs are preferred over large mixed-purpose batches.
