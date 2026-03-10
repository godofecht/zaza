const logEl = document.getElementById("log");
const loadBtn = document.getElementById("load-btn");
const runBtn = document.getElementById("run-btn");

let wasmInstance = null;

function setLog(lines) {
  logEl.textContent = lines.join("\n");
}

async function loadWasm() {
  setLog(["loading wasm_exports_demo.wasm ..."]);
  const response = await fetch("./wasm_exports_demo.wasm");
  const bytes = await response.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes);
  wasmInstance = instance;
  runBtn.disabled = false;
  setLog([
    "wasm loaded",
    `exports: ${Object.keys(instance.exports).join(", ")}`,
    'ready: click "Run Exports"',
  ]);
}

function runDemo() {
  if (!wasmInstance) return;
  const add = wasmInstance.exports.add(20, 22);
  const mulAdd = wasmInstance.exports.mul_add(6, 6, 6);
  setLog([
    "browser wasm run complete",
    `add(20, 22) = ${add}`,
    `mul_add(6, 6, 6) = ${mulAdd}`,
  ]);
}

loadBtn.addEventListener("click", () => {
  loadWasm().catch((error) => {
    setLog(["load failed", String(error)]);
  });
});

runBtn.addEventListener("click", runDemo);
