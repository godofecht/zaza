const articles = [
  {
    id: "start",
    category: "Get started",
    title: "Start with Vex",
    summary: "Build the repo, run the tests, and see a working example in a few minutes.",
    body: `
      <div class="callout"><strong>What you learn</strong><br>How to build the repo, verify it, and run one example that shows Zig and C++ in the same build graph.</div>
      <h3>Before you begin</h3>
      <ul>
        <li>Install Zig 0.14.0 or newer.</li>
        <li>Use Git for normal dependency flows.</li>
        <li>Use Python 3 if you want to try the browser demo later.</li>
      </ul>
      <h3>Step 1</h3>
      <div class="step-card">
        <strong>Open the repo and run the main checks.</strong>
        <pre><code>zig build test
zig build example-matrix</code></pre>
      </div>
      <h3>Step 2</h3>
      <div class="step-card">
        <strong>Run the first example.</strong>
        <pre><code>zig build run-hello-vex</code></pre>
        <p>This example builds one Zig executable and one C++ executable. Then it runs both.</p>
      </div>
      <h3>What just happened</h3>
      <div class="step-group">
        <div class="step-card">
          <strong><code>zig build test</code></strong>
          Runs the repo test coverage for the current build helpers and flows.
        </div>
        <div class="step-card">
          <strong><code>zig build example-matrix</code></strong>
          Runs the verified examples in sequence. This is the fastest way to see the real supported surface.
        </div>
        <div class="step-card">
          <strong><code>zig build run-hello-vex</code></strong>
          Builds and runs a small mixed Zig and C++ example.
        </div>
      </div>
    `,
  },
  {
    id: "first-project",
    category: "Tutorial",
    title: "Build your first project",
    summary: "Create a small executable target with a simple build file.",
    body: `
      <div class="callout"><strong>Goal</strong><br>Make one C++ executable with a clear build file and a run step.</div>
      <h3>Build file</h3>
      <pre><code>const std = @import("std");
const cpp = @import("build/cpp_example.zig");

pub fn build(b: *std.Build) !void {
    const exe = try cpp.CppExample{
        .name = "my_app",
        .kind = .executable,
        .source_files = &.{"src/main.cpp"},
        .public_include_dirs = &.{"include"},
        .public_defines = &.{"MY_APP=1"},
        .configs = &.{.{ .mode = .Debug }},
        .deps_build_system = .Zig,
        .main_build_system = .Zig,
        .cpp_std = "17",
    }.build(b);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run my_app");
    run_step.dependOn(&run_cmd.step);
}</code></pre>
      <h3>How to read this</h3>
      <div class="step-group">
        <div class="step-card">
          <strong><code>.name</code></strong>
          This becomes the target identity.
        </div>
        <div class="step-card">
          <strong><code>.kind = .executable</code></strong>
          This tells Vex to build a runnable program.
        </div>
        <div class="step-card">
          <strong><code>.source_files</code></strong>
          These are the source files that will be compiled.
        </div>
        <div class="step-card">
          <strong><code>b.step("run", ...)</code></strong>
          This creates a command you can call with <code>zig build run</code>.
        </div>
      </div>
      <h3>Run it</h3>
      <pre><code>zig build
zig build run</code></pre>
    `,
  },
  {
    id: "examples",
    category: "Tutorial",
    title: "Learn through examples",
    summary: "Use a few examples in the repo to learn the main ideas without reading everything at once.",
    body: `
      <div class="callout"><strong>Tip</strong><br>Pick one example for each topic. You do not need to read the whole repo in order.</div>
      <table>
        <thead>
          <tr><th>Topic</th><th>Command</th><th>What it teaches</th></tr>
        </thead>
        <tbody>
          <tr><td>Mixed Zig and C++</td><td><code>zig build run-hello-vex</code></td><td>Two language targets in one graph.</td></tr>
          <tr><td>Packaging</td><td><code>zig build package-consumer-run</code></td><td>Install, export, and downstream use.</td></tr>
          <tr><td>Generated code</td><td><code>zig build generated-headers-run</code></td><td>Generate a header before compile time.</td></tr>
          <tr><td>Shared library</td><td><code>zig build shared-plugin-run</code></td><td>Build a shared plugin and load it at runtime.</td></tr>
          <tr><td>Cross compile</td><td><code>zig build cross-compile-cli-report</code></td><td>Build for another target and inspect the artifact.</td></tr>
          <tr><td>WebAssembly</td><td><code>zig build wasm-web-demo-smoke</code></td><td>Stage a browser demo and verify it over HTTP.</td></tr>
        </tbody>
      </table>
      <h3>Next step</h3>
      <p>Open <code>docs/EXAMPLES.md</code> when you want diagrams and per-example command details.</p>
    `,
  },
  {
    id: "syntax",
    category: "Tutorial",
    title: "Read the syntax",
    summary: "Learn the small set of names and patterns that show up again and again in Vex.",
    body: `
      <h3>Target names</h3>
      <div class="step-group">
        <div class="step-card">
          <strong><code>&lt;name&gt;</code></strong>
          Build or stage the artifact.
        </div>
        <div class="step-card">
          <strong><code>&lt;name&gt;-run</code></strong>
          Run something real.
        </div>
        <div class="step-card">
          <strong><code>&lt;name&gt;-report</code></strong>
          Inspect or validate an artifact.
        </div>
        <div class="step-card">
          <strong><code>&lt;name&gt;-serve</code></strong>
          Start a local server.
        </div>
      </div>
      <h3>Useful fields</h3>
      <pre><code>.kind
.source_files
.public_include_dirs
.public_defines
.custom_commands
.generated_source_files
.configs</code></pre>
      <h3>Useful environment variables</h3>
      <table>
        <thead>
          <tr><th>Name</th><th>Use</th></tr>
        </thead>
        <tbody>
          <tr><td><code>VEX_SYSTEM_CMDS</code></td><td>Allow external tools such as Git and CMake when needed.</td></tr>
          <tr><td><code>VEX_PRESET</code></td><td>Select a preset such as debug, release, asan, or lto.</td></tr>
          <tr><td><code>VEX_EXAMPLES</code></td><td>Limit which examples wire into the root graph.</td></tr>
          <tr><td><code>VEX_MODULES_CXX</code></td><td>Override the compiler used by the C++20 modules example.</td></tr>
        </tbody>
      </table>
      <p>For the full syntax surface, read <code>docs/SYNTAX_REFERENCE.md</code>.</p>
    `,
  },
  {
    id: "libraries",
    category: "Tutorial",
    title: "Add a library target",
    summary: "Move from one executable to a real target graph with public includes and downstream use.",
    body: `
      <div class="callout"><strong>Goal</strong><br>Split reusable code into a library and link it into an application.</div>
      <h3>What to look at</h3>
      <pre><code>zig build proof-library-run
zig build interface-object-graph-run</code></pre>
      <h3>The idea</h3>
      <div class="step-group">
        <div class="step-card">
          <strong>Static library</strong>
          Put reusable code in a library target.
        </div>
        <div class="step-card">
          <strong>Public includes</strong>
          Put headers that downstream code needs in <code>.public_include_dirs</code>.
        </div>
        <div class="step-card">
          <strong>Public defines</strong>
          Put compile-time API flags in <code>.public_defines</code>.
        </div>
      </div>
      <h3>Why this matters</h3>
      <p>This is where build systems become more than a compile command. You need target boundaries, not just flags.</p>
    `,
  },
  {
    id: "generated",
    category: "Tutorial",
    title: "Generate code before build",
    summary: "Use a command to create a source file or header, then compile with it as part of the graph.",
    body: `
      <h3>Try the examples</h3>
      <pre><code>zig build generated-code-run
zig build generated-headers-run</code></pre>
      <h3>Pattern</h3>
      <pre><code>.custom_commands = &.{
    .{
        .name = "generate_header",
        .argv = &.{"sh", "scripts/generate_header.sh", "zig-out/gen/message.hpp"},
    },
},
.generated_source_files = &.{"zig-out/gen/generated.cpp"},</code></pre>
      <h3>How to think about it</h3>
      <div class="step-group">
        <div class="step-card">
          <strong>Custom command</strong>
          This creates the file before compile time.
        </div>
        <div class="step-card">
          <strong>Generated file wiring</strong>
          Vex then treats the output as a real input to the target.
        </div>
      </div>
    `,
  },
  {
    id: "packages",
    category: "Tutorial",
    title: "Export a package and use it",
    summary: "Install headers and libraries, write package metadata, and consume that package from another build.",
    body: `
      <h3>Run the package flow</h3>
      <pre><code>zig build package-producer-run
zig build package-consumer-run</code></pre>
      <h3>What the producer writes</h3>
      <ul>
        <li><code>zig-out/include/&lt;name&gt;/...</code></li>
        <li><code>zig-out/lib/...</code></li>
        <li><code>zig-out/share/vex/&lt;name&gt;.json</code></li>
      </ul>
      <h3>Why this is important</h3>
      <p>This is the clean answer to a common CMake workflow. One project exports a usable package. Another project reads it and links against it.</p>
    `,
  },
  {
    id: "wasm",
    category: "Tutorial",
    title: "Ship WebAssembly",
    summary: "Build a wasm module, load it in Node, and stage it for a browser demo.",
    body: `
      <div class="callout"><strong>Three levels</strong><br>Vex supports a WASI module, a freestanding export module, and a browser demo that stages HTML, JavaScript, and wasm together.</div>
      <h3>Try the commands</h3>
      <pre><code>zig build wasm-wasi-report
zig build wasm-exports-run
zig build wasm-web-demo-smoke
zig build wasm-web-demo-serve</code></pre>
      <h3>What each command does</h3>
      <div class="step-group">
        <div class="step-card">
          <strong><code>wasm-wasi-report</code></strong>
          Builds a WASI artifact and validates the output.
        </div>
        <div class="step-card">
          <strong><code>wasm-exports-run</code></strong>
          Builds an exportable wasm module and loads it in Node.
        </div>
        <div class="step-card">
          <strong><code>wasm-web-demo-serve</code></strong>
          Serves the browser demo on <code>http://127.0.0.1:8000</code>.
        </div>
      </div>
    `,
  },
  {
    id: "cmake",
    category: "Migration",
    title: "Move from CMake step by step",
    summary: "Keep the migration simple. Move one target at a time and use CMake only where it is still required.",
    body: `
      <h3>Good migration order</h3>
      <ol>
        <li>Move one application target into <code>build.zig</code>.</li>
        <li>Move one library target and its public include paths.</li>
        <li>Move generated code and packaging flows.</li>
        <li>Keep CMake only for dependencies that still need it.</li>
      </ol>
      <h3>Useful commands</h3>
      <pre><code>zig build cmake-combo-run
zig build cmake-net-run
VEX_SYSTEM_CMDS=1 zig build cmake-shim</code></pre>
      <h3>Mental model</h3>
      <table>
        <thead>
          <tr><th>CMake</th><th>Vex</th></tr>
        </thead>
        <tbody>
          <tr><td><code>CMakeLists.txt</code></td><td><code>build.zig</code></td></tr>
          <tr><td><code>add_executable()</code></td><td>Executable target</td></tr>
          <tr><td><code>add_library()</code></td><td>Library target with <code>.kind</code></td></tr>
          <tr><td><code>add_custom_command()</code></td><td><code>.custom_commands</code></td></tr>
          <tr><td><code>find_package()</code></td><td>Package producer and consumer flow</td></tr>
        </tbody>
      </table>
    `,
  },
  {
    id: "next",
    category: "Reference",
    title: "Where to go next",
    summary: "Use the rest of the repo docs when you need more detail.",
    body: `
      <div class="step-group">
        <div class="step-card">
          <strong><code>docs/EXAMPLES.md</code></strong>
          Use this when you want example-by-example diagrams and command references.
        </div>
        <div class="step-card">
          <strong><code>docs/SYNTAX_REFERENCE.md</code></strong>
          Use this when you want field names, command naming rules, and environment variables.
        </div>
        <div class="step-card">
          <strong><code>docs/ROADMAP.md</code></strong>
          Use this when you want to see what still needs to land for stronger CMake replacement coverage.
        </div>
      </div>
      <h3>Good commands to keep nearby</h3>
      <pre><code>zig build test
zig build example-matrix
zig build package-consumer-run
zig build shared-plugin-run
zig build wasm-web-demo-smoke</code></pre>
    `,
  },
];

const navEl = document.getElementById("nav");
const contentEl = document.getElementById("content");
const searchEl = document.getElementById("search");
const template = document.getElementById("article-template");

function escapeRegExp(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function getArticle(id) {
  return articles.find((article) => article.id === id) || articles[0];
}

function renderNav(filter = "") {
  const q = filter.trim().toLowerCase();
  const filtered = q
    ? articles.filter((article) => (
        `${article.title} ${article.summary} ${article.category} ${article.body}`
      ).toLowerCase().includes(q))
    : articles;

  navEl.innerHTML = "";

  if (!filtered.length) {
    const empty = document.createElement("p");
    empty.textContent = "No tutorials match your search.";
    navEl.appendChild(empty);
    return;
  }

  filtered.forEach((article) => {
    const button = document.createElement("button");
    button.className = "nav-link";
    button.type = "button";
    button.dataset.id = article.id;
    button.textContent = article.title;
    button.addEventListener("click", () => {
      location.hash = article.id;
    });
    navEl.appendChild(button);
  });
}

function highlight(body, query) {
  if (!query) return body;

  const escaped = escapeRegExp(query.trim());
  if (!escaped) return body;

  const rx = new RegExp(`(${escaped})`, "ig");
  return body.replace(rx, "<mark>$1</mark>");
}

function renderArticle(id, query = "") {
  const article = getArticle(id);
  const node = template.content.firstElementChild.cloneNode(true);

  node.querySelector(".article-category").textContent = article.category;
  node.querySelector(".article-title").textContent = article.title;
  node.querySelector(".article-summary").textContent = article.summary;
  node.querySelector(".article-body").innerHTML = highlight(article.body, query);

  contentEl.innerHTML = "";
  contentEl.appendChild(node);

  const active = navEl.querySelector(`.nav-link[data-id="${article.id}"]`);
  navEl.querySelectorAll(".nav-link").forEach((el) => el.classList.remove("active"));
  if (active) active.classList.add("active");
}

function sync() {
  const id = (location.hash || "#start").slice(1);
  const query = searchEl.value.trim();
  renderNav(query);
  renderArticle(id, query);
}

searchEl.addEventListener("input", sync);
window.addEventListener("hashchange", sync);

sync();
