# Zaza JUCE Audio Synth

A JUCE audio application with the audio modules enabled, built through the same JUCE integration.

## What it demonstrates

- The same `cpp.JUCEApplication` path as `examples/juce`, with a wider module set.
- `juce_audio_basics`, `juce_audio_devices`, `juce_audio_formats`, `juce_audio_processors`, `juce_audio_utils`.

## Prerequisites

- `cmake` and `git` on PATH.
- Network access on the first run, to fetch JUCE 8.0.14.
- A long first build. JUCE is compiled from source.

## Build and run

```bash
ZAZA_EXAMPLES=zaza-juce ZAZA_SYSTEM_CMDS=1 zig build zaza-juce
```

## Expected output

```text
[100%] Linking CXX executable ZazaJuce_artefacts/Debug/ZazaJuce.app/Contents/MacOS/ZazaJuce
Copying OS X content ZazaJuce_artefacts/Debug/ZazaJuce.app/Contents/Resources/RecentFilesMenuTemplate.nib
[100%] Built target ZazaJuce
```

## Notes

On macOS the bundle lands at
`examples/zaza-juce/build/ZazaJuce_artefacts/Debug/ZazaJuce.app`.

If the build fails with a `CMakeCache.txt` directory mismatch, the cache was
written by a checkout at a different path. Remove it and rebuild:

```bash
rm -rf examples/zaza-juce/build
```

---

Back to the [example index](../README.md) or the [Zaza wiki](../../docs/WIKI.md).
