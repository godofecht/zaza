<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->
<a id="readme-top"></a>

[![CI][ci-shield]][ci-url]
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]

<br />
<div align="center">

<h3 align="center">Zaza</h3>

  <p align="center">
    A Zig-driven build system for modern C, C++, Zig, Rust, CMake-interop, and WebAssembly workflows.
    <br />
    <a href="docs/WIKI.md"><strong>Read the wiki &raquo;</strong></a>
    <br />
    <br />
    <a href="examples/README.md">View Examples</a>
    &middot;
    <a href="https://github.com/godofecht/zaza/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    &middot;
    <a href="https://github.com/godofecht/zaza/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#example-highlights">Example Highlights</a></li>
    <li><a href="#replacing-cmake">Replacing CMake</a></li>
    <li><a href="#webassembly">WebAssembly</a></li>
    <li><a href="#fast-builds">Fast builds</a></li>
    <li><a href="#tests-and-benchmarks">Tests and benchmarks</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

## About The Project

Zaza makes new native projects feel simpler than CMake without giving up serious target graphs, package flows, generated code, cross-compilation, or browser-adjacent outputs.

**Why Zaza:**
* Zig build graph as the control plane instead of a separate DSL
* First-class mixed-language workflows: C, C++, and Zig in one repo
* Real examples for generated sources, shared plugins, packaging, presets, CMake interop, and wasm
* One verified matrix command for the entire example surface

**Status:** Zaza is usable and heavily example-driven, but it is not pretending to have a final polished API yet. The verified example matrix is runnable with `zig build example-matrix`.

**Start here:** [`docs/WIKI.md`](docs/WIKI.md) is the single-page overview. It covers the problem Zaza solves, how it compares to CMake, a five-minute quickstart, the core concepts, every environment variable, the example matrix, the WebAssembly workflows, and troubleshooting.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

* [![Zig][Zig-badge]][Zig-url]
* C / C++
* CMake (interop layer)
* WebAssembly

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

### Prerequisites

* [Zig](https://ziglang.org/download/) 0.14.1, 0.15.2 or 0.16.0. All three are tested in CI.
* Optional: `cmake` and `git` for the CMake interop and JUCE examples, `cargo` for the Rust example, `node` for the WebAssembly examples.
* Optional: [direnv](https://direnv.net/) for repo-local cache setup.

### Installation

Zaza ships a `build.zig.zon` and is indexed by the Zig package trackers. Fetch it
with the package manager:

```sh
zig fetch --save git+https://github.com/godofecht/zaza
```

Or clone and run the setup, which is the usual flow since build files import
`build_lib/zaza.zig` directly:

```sh
git clone https://github.com/godofecht/zaza.git
cd zaza
./setup.sh
```

[`setup.sh`](setup.sh) reports your Zig version, warns if it is outside the tested range, creates the machine-local `./zig` wrapper if it is missing, lists which optional examples your machine cannot run, and then runs the test suite. It is safe to run repeatedly.
Use `ZIG=/path/to/zig ./setup.sh` to check a specific supported lane, for
example a `zigup`-installed 0.14.1, 0.15.2, or 0.16.0 binary.
The setup uses a Zig-version-specific cache directory by default, so changing
lanes does not reuse a stale build runner from another Zig release.

```text
Toolchain
  ok  zig 0.15.2 (/opt/homebrew/bin/zig)
...
Build Summary: 43/43 steps succeeded; 87/87 tests passed
```

To verify the rest of the surface:

```sh
zig build example-matrix
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Usage

Useful first commands:

```sh
zig build run-hello-zaza
zig build package-consumer-run
zig build mixed-stack-run
zig build wasm-web-demo-smoke
zig build wasm-web-demo-serve
```

If a target needs external tools such as `git` or `cmake`, enable them explicitly:

```sh
ZAZA_SYSTEM_CMDS=1 zig build cmake-shim
```

**Naming conventions:**

| Pattern | Meaning |
| --- | --- |
| `<name>` | Build or stage the artifact |
| `<name>-run` | Execute something real |
| `<name>-report` | Inspect or validate an artifact |
| `<name>-serve` | Start a local server |

**Minimal `build.zig` example:**

```zig
const std = @import("std");
const zaza = @import("build_lib/zaza.zig");

pub fn build(b: *std.Build) !void {
    const exe = try zaza.Target.executable(.{
        .name = "my_app",
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{"include"},
        .public_defines = &.{"MY_APP=1"},
        .cpp_std = "17",
    }).build(b);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run my_app");
    run_step.dependOn(&run_cmd.step);
}
```

`build_lib/zaza.zig` is the stable entry module: import it once and reach the
supported types and functions through it. `zaza.Target` is the C and C++ target
type; `zaza.CppExample` is kept as an alias so existing build files keep
working. The full surface is in [`docs/API.md`](docs/API.md), and the field list
is in the [Syntax Reference](docs/SYNTAX_REFERENCE.md).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Packages

Zaza tracks C and C++ dependencies in `registry/registry.json` and fetches them
into `build.zig.zon`. Discover and inspect them from the CLI:

```sh
zig run scripts/zaza.zig -- list                # every package, with descriptions
zig run scripts/zaza.zig -- search audio        # ranked across name, keywords, description
zig run scripts/zaza.zig -- info juce           # full metadata for one package
zig run scripts/zaza.zig -- fetch fmt           # add it to build.zig.zon
```

`search` scores each package across its name, keywords, and description, so
`search http` finds curl even though the name does not contain the word. Each
registry entry carries a description, keywords, repo, homepage, and license.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Example Highlights

| Workflow | Command |
| --- | --- |
| Mixed Zig + C++ | `zig build run-hello-zaza` |
| Package producer / consumer | `zig build package-consumer-run` |
| Mixed C + C++ + Zig | `zig build mixed-stack-run` |
| Interface + object + static graph | `zig build interface-object-graph-run` |
| Shared plugin loading | `zig build shared-plugin-run` |
| Cross-compile artifact report | `zig build cross-compile-cli-report` |
| C++20 modules | `zig build cxx20-modules-run` |
| WASI artifact validation | `zig build wasm-wasi-report` |
| Host-loaded wasm exports | `zig build wasm-exports-run` |
| Browser wasm demo | `zig build wasm-web-demo-smoke` |

Every example has its own README with prerequisites and an exact command. The index is [`examples/README.md`](examples/README.md). Per-example diagrams and syntax notes live in [`docs/EXAMPLES.md`](docs/EXAMPLES.md).

Plugin, bundle, and resource layouts can stage outputs with `artifact_copies`,
`file_copies`, or the lower-level `zaza.addArtifactCopies` and
`zaza.addFileCopies` helpers. The shared plugin example copies the dynamic
library into `zig-out/share/shared_plugin/plugins/` before the host loads it;
the resources example stages a runtime asset under `zig-out/share`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Replacing CMake

The intent is not to mimic CMake syntax one-for-one. The intent is to cover the workflows people actually need when starting new projects.

| CMake concept | Zaza shape |
| --- | --- |
| `CMakeLists.txt` | `build.zig` |
| `add_executable()` | executable target / `CppExample{ .kind = .executable }` |
| `add_library(STATIC ...)` | `CppExample{ .kind = .static_library }` |
| `target_include_directories()` | include-dir fields on the target |
| `target_compile_definitions()` | `public_defines` / `private_defines` / config defines |
| `add_custom_command()` | `custom_commands` |
| `add_custom_command(TARGET ... POST_BUILD copy ...)` | `artifact_copies`, `file_copies`, and copy helpers |
| `install()` / `export()` | install/export fields and Zaza package metadata |
| `find_package()` consumer flow | package producer / consumer example |

See [`docs/CMAKE_PARITY.md`](docs/CMAKE_PARITY.md) and [`docs/ROADMAP.md`](docs/ROADMAP.md) for the full parity framing.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## WebAssembly

Zaza has concrete wasm workflows:

```sh
zig build wasm-wasi-report
zig build wasm-exports-run
zig build wasm-web-demo
zig build wasm-web-demo-smoke
zig build wasm-web-demo-serve
```

`wasm-web-demo-serve` stages and serves a browser harness at `http://127.0.0.1:8000`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Fast builds

A `zig build` no-op is startup-bound: the build script compiles and runs on
every invocation. `zaza-drive` is a native build driver that skips that. It
reads a manifest, checks source and recorded-header timestamps, and rebuilds
only what changed. Same 16 translation unit project, same machine, same
compiler in every lane:

| phase | zaza-drive | ninja | zig build |
| --- | --- | --- | --- |
| no-op rebuild | 2.3 ms | 3.3 ms | 69.7 ms |
| incremental rebuild | 110.4 ms | 121.4 ms | 106.1 ms |

`zig build drive-native` writes a manifest that uses the system compiler, which
starts about twice as fast as the `zig c++` wrapper. That cuts the incremental
rebuild from 127 ms to 47 ms, about 2.7x. It is an iteration path: the system
compiler differs from Zig's bundled one, so release and cross builds still go
through `zig build` or the faithful `zig build drive`.

The numbers are measured, reproducible with [`tools/zaza-drive/bench.sh`](tools/zaza-drive/bench.sh). Details and the honest tradeoff are in [`tools/zaza-drive/README.md`](tools/zaza-drive/README.md) and [`benchmarks/README.md`](benchmarks/README.md).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Tests and benchmarks

A test or a benchmark is an executable plus a list of run cases, where each case
is data: a label, arguments, an environment, and a working directory. The API in
[`build_lib/test_suite.zig`](build_lib/test_suite.zig) turns that list into the
run steps for you.

```zig
_ = try test_suite.addTest(b, target, .{
    .name = "test-workflows",
    .target = demo,                      // a CppExample
    .cases = &.{
        .{ .label = "unit", .args = &.{"unit"} },
        .{ .label = "integration", .args = &.{"integration"} },
    },
});
```

This gives `test-workflows`, `test-workflows-run`, and a step per case, and
hooks the cases onto `zig build test`. `addBench` is the same shape with release
defaults: it stays off `test`, prints its timings, and forwards
`zig build bench-suite-run -- --reps 9` to the process. Full detail is in
[`docs/WIKI.md`](docs/WIKI.md#testing-and-benchmarks); the two examples are
[`examples/test_workflows`](examples/test_workflows) and
[`examples/bench_suite`](examples/bench_suite).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Roadmap

- [x] Mixed C/C++/Zig target graphs
- [x] Package producer/consumer workflow
- [x] WebAssembly (WASI, host embedding, browser)
- [x] CMake interop layer
- [x] Verified example matrix
- [x] Polished public API: the `build_lib/zaza.zig` facade and [`docs/API.md`](docs/API.md)
- [x] Registry and package discovery: ranked `search`, `zaza info`, richer metadata
- [x] IDE integration: azazel's [VS Code extension and LSP](https://github.com/godofecht/azazel/tree/main/ide) for `project.cue`

See the [open issues](https://github.com/godofecht/zaza/issues) for a full list of proposed features (and known issues). See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the detailed roadmap.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

The current contribution bar is:

```sh
./setup.sh              # runs ZAZA_EXAMPLES=none zig build test --summary all
zig build example-matrix
```

Run `./setup.sh` on 0.14.1, 0.15.2 and 0.16.0 if your change touches build files or Zig sources. The suite should report `43/43 steps succeeded; 87/87 tests passed` on each.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement". Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full repo workflow details.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Top contributors:

<a href="https://github.com/godofecht/zaza/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=godofecht/zaza" alt="contrib.rocks image" />
</a>

## License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contact

Abhishek Shivakumar - security@zaza.build

Project Link: [https://github.com/godofecht/zaza](https://github.com/godofecht/zaza)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Acknowledgments

* [Zig](https://ziglang.org/) - the language and build system that makes this possible
* [Best-README-Template](https://github.com/othneildrew/Best-README-Template) - README template
* All contributors and the open source community

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Repository Layout

| Path | Purpose |
| --- | --- |
| [`build.zig`](build.zig) | Root build graph |
| [`build_lib`](build_lib) | Reusable build helpers |
| [`examples`](examples) | Example projects and workflows |
| [`corpus`](corpus) | External upstream repos rebuilt through Zaza, with native-build comparisons |
| [`tests`](tests) | Zig-side test coverage |
| [`registry`](registry) | Lightweight registry metadata |
| [`wiki`](wiki) | Static docs site |
| [`docs`](docs) | Documentation |
| [`setup.sh`](setup.sh) | Toolchain check, wrapper creation, and test run |

Published at [godofecht.github.io/zaza](https://godofecht.github.io/zaza/).

**Documentation map**

| Document | Covers |
| --- | --- |
| [`docs/WIKI.md`](docs/WIKI.md) | Single-page overview: quickstart, concepts, env vars, troubleshooting |
| [`examples/README.md`](examples/README.md) | Every example, its command, and its purpose |
| [`docs/EXAMPLES.md`](docs/EXAMPLES.md) | Per-example diagrams and syntax focus |
| [`docs/SYNTAX_REFERENCE.md`](docs/SYNTAX_REFERENCE.md) | Full field and command surface |
| [`docs/CMAKE_PARITY.md`](docs/CMAKE_PARITY.md) | Feature-by-feature parity status |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | What is being built next |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
[ci-shield]: https://img.shields.io/github/actions/workflow/status/godofecht/zaza/ci.yml?branch=main&style=for-the-badge&label=CI
[ci-url]: https://github.com/godofecht/zaza/actions/workflows/ci.yml
[contributors-shield]: https://img.shields.io/github/contributors/godofecht/zaza.svg?style=for-the-badge
[contributors-url]: https://github.com/godofecht/zaza/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/godofecht/zaza.svg?style=for-the-badge
[forks-url]: https://github.com/godofecht/zaza/network/members
[stars-shield]: https://img.shields.io/github/stars/godofecht/zaza.svg?style=for-the-badge
[stars-url]: https://github.com/godofecht/zaza/stargazers
[issues-shield]: https://img.shields.io/github/issues/godofecht/zaza.svg?style=for-the-badge
[issues-url]: https://github.com/godofecht/zaza/issues
[license-shield]: https://img.shields.io/github/license/godofecht/zaza.svg?style=for-the-badge
[license-url]: https://github.com/godofecht/zaza/blob/main/LICENSE
[Zig-badge]: https://img.shields.io/badge/Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white
[Zig-url]: https://ziglang.org/
