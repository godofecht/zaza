# JUCE on Windows (Zig 0.14)

Zig 0.14 cannot compile C++ using the MSVC ABI (see Zig issue #18685). This affects any Zaza build
that uses Zig as the C++ compiler on Windows.

## Workarounds

### 1) Use the GNU toolchain ABI (recommended)

```bash
ZAZA_WINDOWS_TOOLCHAIN=gnu zig build juce
```

Or set an explicit target:

```bash
ZAZA_TARGET=x86_64-windows-gnu zig build juce
```

### 2) Use a system toolchain via CMake

If you must use MSVC, switch the build to CMake (system compiler) for the main target.

## Notes
- This repo targets Zig 0.14 for stability.
- When Zig fixes MSVC C++ support, we can remove these workarounds.
