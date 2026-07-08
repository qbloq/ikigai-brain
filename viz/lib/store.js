// UI store — persisted specs in LAYERS (docs/deltas-architecture.md, paso 5):
//
//   viz/specs/org/          the shared genome (git — distributed by pull)
//   viz/specs/roles/<rol>/  role templates (git, central)
//   viz/specs/local/        the personal layer — the ONLY writable one
//
// list() merges the layers with SHADOWING by stable slug id: local beats
// role beats org. create() and every edit write to local/ exclusively —
// org/roles are immutable from the runtime, so touching an org spec forks it
// into local/ with lineage (derived_from: "<layer>/<slug>@<git-sha>" — nothing
// is born without origin). Everything in local/ is therefore a delta BY
// CONSTRUCTION, and every local write auto-commits with a structured message
// (`viz(ui): <verb> <slug>` + Delta-Type/Delta-Scope trailers): git is the
// delta event log — observing this layer is `git log -- viz/specs/local/`.
// Set VIZ_AUTOCOMMIT=0 to disable the auto-commit (e.g. throwaway experiments).
//
// A spec is still { id, name, component|pattern, source|slots, params, … };
// rendering happens on demand from live data, so a saved UI always reflects
// current data. Legacy viz/store/ is migrated once by
// viz/scripts/migrate-store-to-specs.js.

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const SPECS_DIR = path.join(__dirname, "..", "specs");
const ORG_DIR = path.join(SPECS_DIR, "org");
const ROLES_DIR = path.join(SPECS_DIR, "roles");
const LOCAL_DIR = path.join(SPECS_DIR, "local");

function readLayerDir(dir, layer) {
  let files;
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith(".json"));
  } catch {
    return [];
  }
  return files
    .map((f) => {
      try {
        const spec = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
        // _layer/_file are runtime-only (stripped before any write)
        return { ...spec, _layer: layer, _file: path.join(dir, f) };
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

// org → roles/<r> → local, in shadowing order (later wins).
function allLayers() {
  const out = [readLayerDir(ORG_DIR, "org")];
  let roles = [];
  try {
    roles = fs.readdirSync(ROLES_DIR, { withFileTypes: true }).filter((d) => d.isDirectory());
  } catch {
    /* no roles yet */
  }
  for (const r of roles) out.push(readLayerDir(path.join(ROLES_DIR, r.name), `roles/${r.name}`));
  out.push(readLayerDir(LOCAL_DIR, "local"));
  return out;
}

function list() {
  const merged = new Map(); // slug id → spec (later layers shadow earlier)
  for (const layer of allLayers()) for (const spec of layer) merged.set(spec.id, spec);
  return [...merged.values()].sort((a, b) => (a.created_at || "").localeCompare(b.created_at || ""));
}

function get(id) {
  let found = null;
  for (const layer of allLayers()) for (const spec of layer) if (spec.id === id) found = spec;
  return found;
}

// --- local writes (the only writes) + the auto-commit event log --------------

function gitShortSha() {
  try {
    return execFileSync("git", ["-C", REPO_ROOT, "rev-parse", "--short", "HEAD"], { encoding: "utf8" }).trim();
  } catch {
    return null;
  }
}

// Best-effort: stage + commit ONLY the given paths, with the structured
// message the deltas doc mandates. Failure (not a repo, nothing changed,
// git missing) logs and moves on — the UI write must never break on git.
function autoCommit(verb, slug, absFiles) {
  if (process.env.VIZ_AUTOCOMMIT === "0") return;
  const rel = absFiles.map((f) => path.relative(REPO_ROOT, f));
  try {
    execFileSync("git", ["-C", REPO_ROOT, "add", "--", ...rel], { encoding: "utf8" });
    execFileSync(
      "git",
      ["-C", REPO_ROOT, "commit", "-q", "-m", `viz(ui): ${verb} ${slug}`, "-m", "Delta-Type: ui-spec\nDelta-Scope: personal", "--", ...rel],
      { encoding: "utf8" }
    );
  } catch (e) {
    console.warn(`[store] auto-commit falló (${verb} ${slug}): ${(e.stderr || e.message || "").toString().trim()}`);
  }
}

function fileForLocal(id) {
  return path.join(LOCAL_DIR, `${id}.json`);
}

function persistLocal(spec, verb) {
  fs.mkdirSync(LOCAL_DIR, { recursive: true });
  const { _layer, _file, ...clean } = spec;
  const file = fileForLocal(clean.id);
  fs.writeFileSync(file, JSON.stringify(clean, null, 2) + "\n");
  autoCommit(verb, clean.id, [file]);
  return get(clean.id);
}

// Editing a spec that lives in org/ or a role layer forks it into local/ with
// lineage; a spec already in local/ is updated in place.
function forkForWrite(spec) {
  if (spec._layer === "local") return { ...spec };
  const sha = gitShortSha();
  return {
    ...spec,
    scope: "personal",
    derived_from: `${spec._layer}/${spec.id}${sha ? `@${sha}` : ""}`,
  };
}

// --- public API ---------------------------------------------------------------

function slugify(name) {
  const base = String(name || "ui")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  return base || "ui";
}

// A fresh slug never collides with ANY layer (a new UI must not silently
// shadow an org/role spec — shadowing is only for deliberate forks).
function freshSlug(name) {
  const taken = new Set(list().map((u) => u.id));
  const base = slugify(name);
  if (!taken.has(base)) return base;
  for (let i = 2; ; i++) if (!taken.has(`${base}-${i}`)) return `${base}-${i}`;
}

function create({ name, component = "table", source, params = {} }) {
  const now = new Date().toISOString();
  const spec = {
    id: freshSlug(name),
    name: name && name.trim() ? name.trim() : "UI sin nombre",
    component,
    source,
    params,
    scope: "personal",
    created_at: now,
    updated_at: now,
  };
  return persistLocal(spec, "create");
}

// Archiving is a soft-hide: `archived_at` on the spec, nothing deleted. On an
// org/role spec this creates a local FORK carrying the flag (the genome file
// is untouched); unarchiving updates that fork.
function archive(id) {
  const ui = get(id);
  if (!ui) return null;
  const spec = forkForWrite(ui);
  spec.archived_at = new Date().toISOString();
  spec.updated_at = spec.archived_at;
  return persistLocal(spec, "archive");
}

function unarchive(id) {
  const ui = get(id);
  if (!ui) return null;
  const spec = forkForWrite(ui);
  delete spec.archived_at;
  spec.updated_at = new Date().toISOString();
  return persistLocal(spec, "unarchive");
}

// Only local files can be removed. Removing a local shadow "unforks": the
// org/role spec underneath reappears. Genome files are never touched.
function remove(id) {
  const ui = get(id);
  if (!ui || ui._layer !== "local") return false;
  try {
    fs.unlinkSync(ui._file);
  } catch {
    return false;
  }
  autoCommit("remove", id, [ui._file]);
  return true;
}

module.exports = { list, get, create, archive, unarchive, remove, ORG_DIR, ROLES_DIR, LOCAL_DIR };
