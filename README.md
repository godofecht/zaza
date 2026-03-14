<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->
<a id="readme-top"></a>

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]

<br />
<div align="center">

<h3 align="center">Zaza</h3>

  <p align="center">
    A Zig-driven build system for modern C, C++, Zig, CMake-interop, and WebAssembly workflows.
    <br />
    <a href="docs/SYNTAX_REFERENCE.md"><strong>Explore the docs &raquo;</strong></a>
    <br />
    <br />
    <a href="#example-highlights">View Examples</a>
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

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

* [![Zig][Zig-badge]][Zig-url]
* C / C++
* CMake (interop layer)
* WebAssembly

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

### Prerequisites

* [Zig](https://ziglang.org/download/) 0.14.0 or newer
* Git (for dependency fetch flows)
* Optional: [direnv](https://direnv.net/) for repo-local cache setup

### Installation

1. Clone the repo
   ```sh
   git clone https://github.com/godofecht/zaza.git
   ```
2. Enter the project directory
   ```sh
   cd zaza
   ```
3. (Optional) Allow direnv
   ```sh
   direnv allow
   ```
4. Verify the build
   ```sh
   zig build test
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
const cpp = @import("build/cpp_example.zig");

pub fn build(b: *std.Build) !void {
    const exe = try cpp.CppExample.executable(.{
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

_For the full syntax surface, please refer to the [Syntax Reference](docs/SYNTAX_REFERENCE.md)._

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

Full per-example explanations and diagrams live in [`docs/EXAMPLES.md`](docs/EXAMPLES.md).

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

## Roadmap

- [x] Mixed C/C++/Zig target graphs
- [x] Package producer/consumer workflow
- [x] WebAssembly (WASI, host embedding, browser)
- [x] CMake interop layer
- [x] Verified example matrix
- [ ] Polished public API
- [ ] Registry and package discovery
- [ ] IDE integration (language server, VS Code extension)

See the [open issues](https://github.com/godofecht/zaza/issues) for a full list of proposed features (and known issues). See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the detailed roadmap.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

The current contribution bar is:

```sh
zig build test
zig build example-matrix
```

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
| [`tests`](tests) | Zig-side test coverage |
| [`registry`](registry) | Lightweight registry metadata |
| [`wiki`](wiki) | Static docs site |
| [`docs`](docs) | Documentation |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
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
