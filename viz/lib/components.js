// Component registry — the assembly point of the composition tower
// (docs/deltas-architecture.md): kernel (lib/kit.js) → blocks (blocks/) →
// patterns (patterns/) → pages (pages/). Registration is by convention, never
// by editing this file:
//   · every viz/pages/*.js exports { id, render(ui), manifest } — a PAGE
//     (renderable as a saved UI spec);
//   · a viz/blocks/*.js that exports an `id` is a ROUTED BLOCK — it owns SSE
//     fragments (`frags`) and/or write actions (`acts`) dispatched under
//     GET /c/:id/frag/:name · POST /c/:id/act/:name.
// Pages and routed blocks share ONE flat namespace (collision = boot error).
//
// Manifests (paso 3): a page's { consumes, overridable } is validated against
// the source's `emits`/args by validateSpec(); a block with acts declares
// `writes` — the bash scripts its ctx.run() may execute (see lib/actions.js).

const fs = require("node:fs");
const path = require("node:path");
const { escape } = require("./kit");
const { SOURCES } = require("./datasources");

const PAGES_DIR = path.join(__dirname, "..", "pages");
const BLOCKS_DIR = path.join(__dirname, "..", "blocks");
const PATTERNS_DIR = path.join(__dirname, "..", "patterns");

// Fails loudly at startup on a malformed or duplicate module — a broken
// registry should never boot half-silent.
const PAGES = new Map(); // id → page (renderable)
const COMPONENTS = new Map(); // id → page | block (dispatchable / slot-fillable)
const PATTERNS = new Map(); // id → pattern (spec v2 addressable)

for (const f of fs.readdirSync(PAGES_DIR).filter((f) => f.endsWith(".js")).sort()) {
  const mod = require(path.join(PAGES_DIR, f));
  if (!mod || typeof mod.render !== "function" || !mod.id) {
    throw new Error(`Página inválida en pages/${f}: debe exportar { id, render }`);
  }
  if (COMPONENTS.has(mod.id)) throw new Error(`Componente duplicado: "${mod.id}" (pages/${f})`);
  PAGES.set(mod.id, mod);
  COMPONENTS.set(mod.id, mod);
}

// Blocks opt in by exporting an `id`: routed blocks (frags/acts) AND
// slot-fillable blocks (manifest.slot) — both are addressable by name.
for (const f of fs.readdirSync(BLOCKS_DIR).filter((f) => f.endsWith(".js")).sort()) {
  const mod = require(path.join(BLOCKS_DIR, f));
  if (!mod || !mod.id) continue; // plain render block — composed by pages, not addressed
  if (COMPONENTS.has(mod.id)) throw new Error(`Componente duplicado: "${mod.id}" (blocks/${f})`);
  COMPONENTS.set(mod.id, mod);
}

// Patterns: spec v2 records address them by name ({ pattern, <slots…> }).
// One namespace across everything — a pattern colliding with a component id
// would make specs ambiguous to read.
for (const f of fs.readdirSync(PATTERNS_DIR).filter((f) => f.endsWith(".js")).sort()) {
  const mod = require(path.join(PATTERNS_DIR, f));
  if (!mod || !mod.id) continue;
  if (typeof mod.render !== "function") throw new Error(`Patrón inválido en patterns/${f}: debe exportar render`);
  if (COMPONENTS.has(mod.id) || PATTERNS.has(mod.id)) throw new Error(`Id duplicado: "${mod.id}" (patterns/${f})`);
  PATTERNS.set(mod.id, mod);
}

function listPages() {
  return [...PAGES.keys()];
}

function getComponent(id) {
  return COMPONENTS.get(id) || null;
}

// The manifest of a page ('' / unknown → the generic table's), or null.
// Used by withParamOverrides — hence the table fallback (render semantics).
function getManifest(componentId) {
  const page = PAGES.get(componentId || "table");
  return (page && page.manifest) || null;
}

// Which query params the browser may override for THIS spec: a v1 spec
// delegates to its page's manifest; a v2 (pattern) spec to the union of its
// slot blocks' `overridable` lists.
function overridableFor(ui) {
  if (!ui) return [];
  if (ui.pattern) {
    const pat = PATTERNS.get(ui.pattern);
    const keys = new Set();
    for (const name of Object.keys((pat && pat.manifest && pat.manifest.slots) || {})) {
      const blk = ui[name] && ui[name].block ? COMPONENTS.get(ui[name].block) : null;
      for (const k of (blk && blk.manifest && blk.manifest.overridable) || []) keys.add(k);
    }
    return [...keys];
  }
  const m = getManifest(ui.component);
  return (m && m.overridable) || [];
}

// Route a frag/act to its component's handler. Returns the handler's patches
// normalized to an array of HTML strings, or null when nothing matches (404).
// Handlers may be async (e.g. io-bind awaits meetico); errors propagate.
async function dispatch(componentId, kind, name, ctx) {
  const mod = COMPONENTS.get(componentId);
  const map = mod && (kind === "frag" ? mod.frags : kind === "act" ? mod.acts : null);
  const fn = map && Object.prototype.hasOwnProperty.call(map, name) && map[name];
  if (typeof fn !== "function") return null;
  const out = await fn(ctx);
  return Array.isArray(out) ? out : [out];
}

// Validate a spec_version-2 record ({ pattern, <slot>: {block, source?,
// params?, frag?} }) against the pattern's slot contract — mechanically, per
// slot: the named block exists, declares the right manifest.slot, its
// `consumes` matches the slot source's `emits`, an explicit frag exists, and
// params stay inside (source args ∪ the block's overridable).
function validateSpecV2(spec) {
  const errors = [];
  const warnings = [];
  const pat = PATTERNS.get(spec.pattern);
  if (!pat) {
    errors.push(`Patrón desconocido: «${spec.pattern}» — esta UI requiere actualizar el genoma.`);
    return { ok: false, errors, warnings };
  }
  for (const [name, req] of Object.entries((pat.manifest && pat.manifest.slots) || {})) {
    const filler = spec[name] || {};
    const blk = filler.block ? COMPONENTS.get(filler.block) : null;
    const bm = (blk && blk.manifest) || {};
    if (!filler.block) errors.push(`El slot ${name} no declara bloque.`);
    else if (!blk) errors.push(`Bloque desconocido en ${name}: «${filler.block}» — requiere actualizar el genoma.`);
    else if (bm.slot !== req.slot) errors.push(`«${filler.block}» no puede llenar el slot ${name} (declara slot=${bm.slot || "ninguno"}).`);
    if (filler.frag && blk && !(blk.frags && blk.frags[filler.frag])) {
      errors.push(`«${filler.block}» no tiene el frag «${filler.frag}».`);
    }
    if (req.source) {
      const src = filler.source ? SOURCES[filler.source] : null;
      if (!filler.source) errors.push(`El slot ${name} no declara fuente.`);
      else if (!src) errors.push(`Fuente desconocida en ${name}: «${filler.source}».`);
      else {
        if (bm.consumes && src.emits && bm.consumes !== src.emits) {
          errors.push(`Forma incompatible: «${filler.source}» emite ${src.emits} y «${filler.block}» consume ${bm.consumes}.`);
        }
        const allowed = new Set([...Object.keys(src.args || {}), ...(bm.overridable || [])]);
        for (const k of Object.keys({ ...(filler.params || {}), ...(spec.params || {}) })) {
          if (!allowed.has(k)) warnings.push(`Param «${k}» no es arg de «${filler.source}» ni overridable de «${filler.block}».`);
        }
      }
    }
  }
  return { ok: !errors.length, errors, warnings };
}

// Validate one UI spec against the registry + SOURCES: component exists,
// source exists, the source's `emits` matches the page's `consumes`, and every
// param is either a whitelisted source arg or declared `overridable` by the
// page. Unknown params on an already-saved spec are a *warning*, not an error
// (old specs must keep rendering); the create form treats warnings as errors.
// A spec with `pattern` takes the v2 path (slot validation).
function validateSpec(spec) {
  if (spec.pattern) return validateSpecV2(spec);
  const errors = [];
  const warnings = [];
  const comp = spec.component || "table";
  const page = PAGES.get(comp);
  if (!page) errors.push(`Componente desconocido: «${comp}» — esta UI requiere actualizar el genoma.`);
  const src = spec.source ? SOURCES[spec.source] : null;
  if (!spec.source) errors.push("La spec no declara fuente (source).");
  else if (!src) errors.push(`Fuente desconocida: «${spec.source}».`);
  const m = page && page.manifest;
  if (m && m.consumes && src && src.emits && src.emits !== m.consumes) {
    errors.push(
      `Forma incompatible: la fuente «${spec.source}» emite ${src.emits} y el componente «${comp}» consume ${m.consumes}.`
    );
  }
  if (src) {
    const allowed = new Set([...Object.keys(src.args || {}), ...((m && m.overridable) || [])]);
    for (const k of Object.keys(spec.params || {})) {
      if (!allowed.has(k)) warnings.push(`Param «${k}» no es arg de «${spec.source}» ni overridable de «${comp}».`);
    }
  }
  return { ok: !errors.length, errors, warnings };
}

// Version-skew degradation (docs/deltas-architecture.md): a spec that names a
// component this genome doesn't have renders an explanation, not garbage.
function degradeCard(ui, errors) {
  return `<section id="pane" class="flex-1 p-8 overflow-auto">
    <div class="max-w-xl rounded-lg border border-amber-300 bg-amber-50 p-5">
      <p class="text-sm font-semibold text-amber-800 mb-1">Esta UI requiere actualizar el genoma</p>
      <p class="text-xs text-amber-700 mb-3">«${escape(ui.name)}» no se puede renderizar con los componentes de este fork:</p>
      <ul class="list-disc list-inside text-xs text-amber-700 space-y-0.5">${errors.map((e) => `<li>${escape(e)}</li>`).join("")}</ul>
      <p class="text-[11px] text-amber-600 mt-3 font-mono">git pull upstream — o corrige la spec (component: «${escape(ui.component || "")}»).</p>
    </div>
  </section>`;
}

// Render a saved UI spec into the pane HTML (a #pane element, id-matched by SSE).
// A spec with `pattern` is v2: validate, resolve its slot block names to
// modules, and hand them to the pattern. Otherwise v1: empty component falls
// through to the generic `table` page (original semantics); an *unknown*
// component degrades gracefully (version skew).
function renderPane(ui) {
  if (!ui) {
    return `<section id="pane" class="flex-1 p-8">
      <div class="h-full flex items-center justify-center text-slate-400">
        <p>Selecciona una UI en el panel izquierdo, o crea una nueva.</p>
      </div></section>`;
  }
  if (ui.pattern) {
    const v = validateSpecV2(ui);
    if (!v.ok) return degradeCard(ui, v.errors);
    const pat = PATTERNS.get(ui.pattern);
    const slots = {};
    for (const name of Object.keys((pat.manifest && pat.manifest.slots) || {})) {
      slots[name] = { ...ui[name], block: COMPONENTS.get(ui[name].block) };
    }
    return pat.render(ui, slots);
  }
  if (ui.component && !PAGES.has(ui.component)) {
    return degradeCard(ui, validateSpec(ui).errors);
  }
  const page = PAGES.get(ui.component || "table");
  return page.render(ui);
}

module.exports = { renderPane, listPages, getComponent, getManifest, overridableFor, dispatch, validateSpec, escape };
