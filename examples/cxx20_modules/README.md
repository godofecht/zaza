# C++20 Modules Example

This example intentionally does **not** use `zig c++`.

On this machine:

- `zig c++` rejects `c++-module` directly
- `zig c++` ignores `-fmodule-output`

So the working strategy here is to use a compiler with usable C++20 modules
support directly. The current default is Homebrew LLVM:

- `/opt/homebrew/opt/llvm/bin/clang++`

Override with:

```bash
VEX_MODULES_CXX=/path/to/clang++ ./zig build cxx20-modules-run
```
