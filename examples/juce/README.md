# JUCE

A JUCE GUI application driven from Zaza through JUCE's own CMake integration.

## What it demonstrates

- `cpp.JUCEApplication` generating a `CMakeLists.txt` and running the JUCE CMake build.
- JUCE module selection from a Zig config struct.

## Prerequisites

- `cmake` and `git` on PATH.
- Network access on the first run, to fetch JUCE 8.0.14.
- A long first build. JUCE is compiled from source.

## Build and run

```bash
ZAZA_EXAMPLES=juce ZAZA_SYSTEM_CMDS=1 zig build juce
```

## Expected output

```text
[100%] Linking CXX executable JuceExample_artefacts/Debug/JuceExample.app/Contents/MacOS/JuceExample
Copying OS X content JuceExample_artefacts/Debug/JuceExample.app/Contents/Resources/RecentFilesMenuTemplate.nib
[100%] Built target JuceExample
```

## Notes

On macOS the bundle lands at
`examples/juce/build/JuceExample_artefacts/Debug/JuceExample.app`.

See [`docs/JUCE_WINDOWS.md`](../../docs/JUCE_WINDOWS.md) for the Windows notes.

If the build fails with a `CMakeCache.txt` directory mismatch, the cache was
written by a checkout at a different path. Remove it and rebuild:

```bash
rm -rf examples/juce/build
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
