# Corpus finding: libvaxis

[libvaxis](https://github.com/rockorager/libvaxis) is the corpus issue's
"generated table workflow as a custom command proof" candidate.

## Finding — no C/C++ surface; out of scope for the C/C++ graph layer

libvaxis is **pure Zig**: the checkout contains **zero** `.c`, `.cc`, `.cpp`, or
C header files. Its "generated table" is the Unicode/grapheme data produced at
build time by its Zig dependencies — `uucode` (lazy) and `zigimg` — through the
Zig build graph, not a C/C++ custom command.

| | |
|---|---|
| Repository | https://github.com/rockorager/libvaxis |
| Commit | `5ca495f09f413c66789d9c5061359b941a8d82c2` |
| Requires | Zig **0.16.0**; deps: `zigimg`, `uucode` (git) |
| C/C++ sources | none |

Because Zaza's replacement value is its **C/C++** target graph, there is no
target slice here to rebuild through that layer — a Zaza build file for libvaxis
would either re-declare its Zig modules (which `zig build` already does natively)
or reimplement the `uucode` codegen, neither of which validates the C/C++ graph.

The generic idea behind this candidate — proving Zaza's **custom-command /
generated-source** support — is better demonstrated with a C/C++ generator (a
tool that emits `.c`/`.h` consumed by a C/C++ target). Zaza already exercises that
shape in `examples/generated_code` and `examples/generated_headers`; a dedicated
external-corpus proof of it should pick a C/C++ project with a real codegen step
rather than a pure-Zig one.

## Recommendation

Drop libvaxis as a C/C++ corpus candidate (it is not a fit), and if a
custom-command corpus proof is wanted, choose a C/C++ codegen project instead.

## Recorded environment

Inspected with Zig 0.16.0; no build attempted (no C/C++ slice to build).
