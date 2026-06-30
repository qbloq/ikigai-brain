// UI store — each generated page is persisted as one JSON file in viz/store/,
// named <id>.json, so it survives restarts and is reachable by URL (/u/<id>).
//
// A UI record is a *spec*, not rendered HTML: { id, name, component, source,
// params, created_at }. Rendering happens on demand from the live data, so a
// saved UI always reflects current data.

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const STORE_DIR = path.join(__dirname, "..", "store");

function ensureDir() {
  fs.mkdirSync(STORE_DIR, { recursive: true });
}

function fileFor(id) {
  return path.join(STORE_DIR, `${id}.json`);
}

function list() {
  ensureDir();
  return fs
    .readdirSync(STORE_DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => {
      try {
        return JSON.parse(fs.readFileSync(path.join(STORE_DIR, f), "utf8"));
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => (a.created_at || "").localeCompare(b.created_at || ""));
}

function get(id) {
  try {
    return JSON.parse(fs.readFileSync(fileFor(id), "utf8"));
  } catch {
    return null;
  }
}

function create({ name, component = "table", source, params = {} }) {
  ensureDir();
  const id = crypto.randomUUID().slice(0, 8);
  const ui = {
    id,
    name: name && name.trim() ? name.trim() : `UI ${id}`,
    component,
    source,
    params,
    created_at: new Date().toISOString(),
  };
  fs.writeFileSync(fileFor(id), JSON.stringify(ui, null, 2) + "\n");
  return ui;
}

function remove(id) {
  try {
    fs.unlinkSync(fileFor(id));
    return true;
  } catch {
    return false;
  }
}

// On a fresh store, seed a few example UIs so the left panel isn't empty.
function seedIfEmpty() {
  if (list().length) return;
  create({ name: "Tareas", source: "tasks", component: "tasks", params: { open: "1", limit: "0" } });
  create({ name: "Editor de IO", source: "tasks", component: "task-editor", params: { open: "1", limit: "0" } });
  create({ name: "Proyectos", source: "projects", params: {} });
  create({ name: "Equipo", source: "team", params: {} });
  create({
    name: "Dashboard · David Guerrero",
    component: "dashboard",
    source: "dashboard",
    params: { project: "David Guerrero", from: "2026-06-01", to: "2026-06-30" },
  });
  create({ name: "SOPs & Arquetipos", source: "sops", component: "sop-tree", params: {} });
}

module.exports = { list, get, create, remove, seedIfEmpty, STORE_DIR };
