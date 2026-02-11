const articles = [
  {
    id: "overview",
    category: "Foundations",
    title: "What Vex Is",
    summary: "Vex is a Zig-powered build workflow for C++ and mixed Zig/C++ projects that aims to replace day-to-day CMake usage with one consistent toolchain.",
    body: `
      <p>Vex uses <code>build.zig</code> as the build source of truth. Instead of writing custom logic in CMake language, you define targets and dependencies in Zig code.</p>
      <p>In this repository, Vex already supports pure C++, pure Zig, and mixed-language examples, with optional CMake fallback only when a dependency requires it.</p>
      <div class="notice"><strong>Core idea:</strong> default to Zig-native builds, and keep CMake as an opt-in compatibility shim rather than the default runtime dependency.</div>
      <h3>Current project intent</h3>
      <ul>
        <li>Faster iteration with <code>zig build</code> and incremental builds.</li>
        <li>Clear dependency model via <code>build.zig.zon</code> and local vendoring when desired.</li>
        <li>Pragmatic migration path for projects that are currently CMake-first.</li>
      </ul>
    `,
  },
  {
    id: "quickstart",
    category: "Getting Started",
    title: "How To Use Vex Clearly",
    summary: "Minimal, practical commands for first build, test, examples, and compatibility modes.",
    body: `
      <h3>1. Build and test</h3>
      <pre><code>zig build
zig build test</code></pre>
      <h3>2. Run representative examples</h3>
      <pre><code>zig build hello-vex
zig build hello-vex run
zig build cmake-combo
zig build cmake-net</code></pre>
      <h3>3. Select execution mode</h3>
      <p>Use one of these two modes depending on your dependency graph:</p>
      <ul>
        <li><strong>Zero-shell mode:</strong> <code>VEX_SYSTEM_CMDS=0 zig build</code> (no git/cmake shell calls).</li>
        <li><strong>Compatibility mode:</strong> <code>VEX_SYSTEM_CMDS=1 zig build</code> (allows git/cmake for CMake-only deps).</li>
      </ul>
      <h3>4. Auto-fetch registry dependencies</h3>
      <pre><code>zig build</code></pre>
      <p>Vex auto-fetches required deps into <code>build.zig.zon</code> and updates <code>vex.lock</code>. Disable with <code>VEX_REGISTRY=0</code>.</p>
      <h3>5. Presets</h3>
      <pre><code>VEX_PRESET=release zig build</code></pre>
      <h3>6. Limit enabled examples</h3>
      <pre><code>VEX_EXAMPLES=juce zig build</code></pre>
    `,
  },
  {
    id: "capabilities",
    category: "Reference",
    title: "Capabilities Matrix",
    summary: "What Vex can do today and what behavior to expect when replacing CMake-centric flows.",
    body: `
      <table>
        <thead>
          <tr><th>Capability</th><th>Status in this repo</th><th>Operational note</th></tr>
        </thead>
        <tbody>
          <tr><td>C++ builds</td><td>Available</td><td>Standard use via <code>zig build</code> and C++ source targets.</td></tr>
          <tr><td>Mixed Zig + C++</td><td>Available</td><td>See <code>hello-vex</code> example for both target types.</td></tr>
          <tr><td>CMake dependency shim</td><td>Available</td><td>Enable with <code>VEX_SYSTEM_CMDS=1</code> for packages that only ship CMake.</td></tr>
          <tr><td>Registry auto-fetch</td><td>Available</td><td>Runs during <code>zig build</code>, writes into <code>build.zig.zon</code> and <code>vex.lock</code>.</td></tr>
          <tr><td>Presets</td><td>Available</td><td>Use <code>VEX_PRESET=debug|release|relwithdebinfo|minsizerel</code>.</td></tr>
          <tr><td>Cross-platform compiler backend</td><td>Available via Zig</td><td>Leverages Zig toolchain and target support.</td></tr>
          <tr><td>Lockfile maturity</td><td>Roadmap</td><td>Roadmap calls for fetched git SHA lock behavior.</td></tr>
          <tr><td>IDE richness</td><td>Partial / growing</td><td>compile_commands.json is emitted for Zig builds; CMake builds enable export.</td></tr>
          <tr><td>Generator expressions</td><td>Subset</td><td>Supports <code>$&lt;CONFIG:...&gt;</code> filtering in list fields.</td></tr>
        </tbody>
      </table>
      <p>Practical takeaway: Vex already covers most build orchestration for new projects. Remaining gaps are mostly around ecosystem tooling maturity rather than core compilation capability.</p>
    `,
  },
  {
    id: "install-export",
    category: "Reference",
    title: "Install + Export",
    summary: "Install headers/libs and emit a CMake config for downstream consumers.",
    body: `
      <h3>Install headers/libs</h3>
      <pre><code>pub var example = cpp.CppExample{
    .name = "hello_vex_cpp",
    .source_files = &.{"src/main.cpp"},
    .install_headers = &.{"include/hello_vex.h"},
    .install_libs = &.{"zig-out/lib/libhello.a"},
    .export_cmake = true,
};</code></pre>
      <h3>Outputs</h3>
      <ul>
        <li><code>zig-out/include/&lt;name&gt;/...</code></li>
        <li><code>zig-out/lib/...</code></li>
        <li><code>zig-out/cmake/&lt;name&gt;/&lt;name&gt;Config.cmake</code></li>
      </ul>
    `,
  },
  {
    id: "cmake-map",
    category: "Migration",
    title: "CMake To Vex Mental Model",
    summary: "Direct concept mapping so teams can migrate with less friction.",
    body: `
      <table>
        <thead>
          <tr><th>CMake concept</th><th>Vex/Zig equivalent</th></tr>
        </thead>
        <tbody>
          <tr><td><code>CMakeLists.txt</code></td><td><code>build.zig</code></td></tr>
          <tr><td><code>add_executable()</code></td><td><code>b.addExecutable(...)</code> or <code>CppExample.build(...)</code></td></tr>
          <tr><td><code>target_include_directories()</code></td><td><code>exe.addIncludePath(...)</code></td></tr>
          <tr><td><code>target_compile_options()</code></td><td><code>.cpp_flags = &.{...}</code></td></tr>
          <tr><td>FetchContent / ExternalProject</td><td>Dependency declarations and zon package entries</td></tr>
          <tr><td><code>cmake --build</code></td><td><code>zig build</code></td></tr>
        </tbody>
      </table>
      <h3>Minimal migration process</h3>
      <ol>
        <li>Model one target in <code>build.zig</code> without deleting CMake files.</li>
        <li>Move include paths and compile flags.</li>
        <li>Replace FetchContent usage with zon or local deps where possible.</li>
        <li>Leave a temporary CMake shim only for outlier dependencies.</li>
        <li>Switch CI default command from <code>cmake --build</code> to <code>zig build</code>.</li>
      </ol>
    `,
  },
  {
    id: "replace-ecosystem",
    category: "Strategy",
    title: "Replacing The CMake Ecosystem",
    summary: "A realistic replacement strategy: reduce CMake scope first, then remove it from critical paths.",
    body: `
      <h3>Goal</h3>
      <p>Stop treating CMake as the central orchestration layer. Keep it only where unavoidable, and make Zig-native builds the default path for developers and CI.</p>
      <h3>Phased rollout</h3>
      <ol>
        <li><strong>Phase 1: Dual-run confidence</strong>.<br>Run Vex and CMake in CI for the same targets; compare artifacts and timing.</li>
        <li><strong>Phase 2: Default switch</strong>.<br>Make <code>zig build</code> the default in docs and CI. Keep CMake jobs as fallback only.</li>
        <li><strong>Phase 3: Shim isolation</strong>.<br>Restrict CMake invocation to a small compatibility layer behind <code>VEX_SYSTEM_CMDS=1</code>.</li>
        <li><strong>Phase 4: Ecosystem replacement</strong>.<br>Move dependencies to zon/local/vendor flow; remove CMake-only packages where feasible.</li>
      </ol>
      <h3>What this replaces in practice</h3>
      <ul>
        <li>CMake script authoring for primary targets.</li>
        <li>Most generator-specific configuration churn.</li>
        <li>Split mental model across CMake + external dependency fetch glue.</li>
      </ul>
      <h3>What remains during transition</h3>
      <ul>
        <li>Some third-party CMake-only libraries until alternatives or wrappers are in place.</li>
        <li>Tooling that currently reads only CMake metadata (temporary adapters may still be needed).</li>
      </ul>
    `,
  },
  {
    id: "roadmap",
    category: "Roadmap",
    title: "CMake Replacement Roadmap",
    summary: "Open issues and milestones for parity, compatibility, and tooling.",
    body: `
      <h3>Top issues</h3>
      <ul>
        <li>Target-level parity: include dirs, compile defs, link libs (Issue #2) — in progress.</li>
        <li>Install/export/find_package workflow (Issue #3).</li>
        <li>Generator expressions + preset profiles (Issue #4).</li>
        <li>Windows toolchain + MSVC ABI workaround (Issue #5).</li>
        <li>IDE tooling: compile_commands + manifest (Issue #6).</li>
        <li>Registry + lockfile (Issue #7).</li>
      </ul>
      <p>Goal: make <code>zig build</code> a drop-in replacement for most CMake workflows while retaining a clean migration path.</p>
    `,
  },
  {
    id: "governance",
    category: "Operations",
    title: "Adoption Policy And Guardrails",
    summary: "Team-level rules to keep migration predictable and avoid falling back into CMake-first habits.",
    body: `
      <h3>Recommended team policy</h3>
      <ul>
        <li>All new targets must land with <code>build.zig</code> definitions first.</li>
        <li>CMake changes require a clear reason (e.g. third-party blocker) and a deprecation note.</li>
        <li>CI must publish build times for <code>zig build</code> to track migration impact.</li>
        <li>Dependency additions should prefer zon or vendored artifacts before CMake fetch scripts.</li>
      </ul>
      <h3>Success metrics</h3>
      <ul>
        <li>Percent of targets built without CMake.</li>
        <li>Average clean build and incremental build times.</li>
        <li>Number of dependencies still requiring CMake shim.</li>
        <li>Failure rate by build mode (<code>VEX_SYSTEM_CMDS=0</code> vs <code>=1</code>).</li>
      </ul>
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
    ? articles.filter((a) => (`${a.title} ${a.summary} ${a.category}`).toLowerCase().includes(q))
    : articles;

  navEl.innerHTML = "";

  if (!filtered.length) {
    const empty = document.createElement("p");
    empty.textContent = "No sections match your search.";
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
  const id = (location.hash || "#overview").slice(1);
  const query = searchEl.value.trim();
  renderNav(query);
  renderArticle(id, query);
}

searchEl.addEventListener("input", sync);
window.addEventListener("hashchange", sync);

sync();
