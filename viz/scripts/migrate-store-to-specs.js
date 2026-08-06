#!/usr/bin/env node
// One-time migration: legacy viz/store/*.json → the layered spec store
// (viz/specs/, docs/deltas-architecture.md paso 5).
//
//   · A stored spec that IS one of the org seeds (matched by component+source
//     [+params.by for charts]) is dropped — the org/ genome file covers it.
//     If it was archived, a local FORK of the org twin keeps that personal
//     flag (archiving is personal state; the genome is immutable).
//   · Everything else is a personal creation by definition → moved to
//     viz/specs/local/ (id preserved, so /u/<id> URLs keep working).
//
// Idempotent: an empty/missing viz/store/ is a no-op. Run: node viz/scripts/migrate-store-to-specs.js

const fs = require("node:fs");
const path = require("node:path");

const VIZ = path.resolve(__dirname, "..");
const STORE = path.join(VIZ, "store");
const ORG = path.join(VIZ, "specs", "org");
const LOCAL = path.join(VIZ, "specs", "local");

// (component, source[, by]) → org slug. Mirrors the seeds in viz/specs/org/.
function orgTwin(s) {
  const key = `${s.component || "table"}|${s.source}`;
  const MAP = {
    "tasks|tasks": "tareas",
    "task-editor|tasks": "editor-io",
    "meetings|meetings": "reuniones",
    "table|projects": "proyectos",
    "table|team": "equipo",
    "dashboard|dashboard": "dashboard-david-guerrero",
    "sop-tree|sops": "sops-arquetipos",
    "localdb|localdbs": "bases-locales",
  };
  if (key === "chart|task_stats") {
    return { status: "tareas-por-estado", project: "tareas-por-proyecto" }[(s.params || {}).by] || null;
  }
  return MAP[key] || null;
}

let files = [];
try {
  files = fs.readdirSync(STORE).filter((f) => f.endsWith(".json"));
} catch {
  /* no legacy store */
}
if (!files.length) {
  console.log("viz/store/ vacío — nada que migrar.");
  process.exit(0);
}
fs.mkdirSync(LOCAL, { recursive: true });

for (const f of files) {
  const p = path.join(STORE, f);
  const spec = JSON.parse(fs.readFileSync(p, "utf8"));
  const twin = orgTwin(spec);
  if (twin && !spec.archived_at) {
    fs.unlinkSync(p);
    console.log(`seed  ${spec.id} «${spec.name}» → cubierta por org/${twin} (eliminada)`);
  } else if (twin && spec.archived_at) {
    const org = JSON.parse(fs.readFileSync(path.join(ORG, `${twin}.json`), "utf8"));
    const fork = { ...org, scope: "personal", derived_from: `org/${twin}`, archived_at: spec.archived_at, updated_at: spec.archived_at };
    fs.writeFileSync(path.join(LOCAL, `${twin}.json`), JSON.stringify(fork, null, 2) + "\n");
    fs.unlinkSync(p);
    console.log(`fork  ${spec.id} «${spec.name}» → local/${twin} (conserva archivada)`);
  } else {
    const personal = { ...spec, scope: "personal", updated_at: spec.updated_at || spec.created_at };
    fs.writeFileSync(path.join(LOCAL, `${spec.id}.json`), JSON.stringify(personal, null, 2) + "\n");
    fs.unlinkSync(p);
    console.log(`local ${spec.id} «${spec.name}» → local/${spec.id}`);
  }
}
console.log("Migración completa.");
