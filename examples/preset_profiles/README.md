# Preset Profiles Example

This example makes the active `VEX_PRESET` visible in program output.

Verified modes in this environment:

- default: works

Known environment-specific limitations on this machine/toolchain:

- `VEX_PRESET=asan` fails to link because the AddressSanitizer runtime is not available
- `VEX_PRESET=lto` fails because Zig reports that LTO requires using LLD here

That means the example is still useful as a preset/profile proof, but `asan` and
`lto` are currently constrained by the local toolchain rather than by the
example itself.
