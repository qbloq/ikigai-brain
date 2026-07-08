// Component registry — the assembly point of the composition tower
// (docs/deltas-architecture.md): kernel (lib/kit.js) → blocks (blocks/) →
// patterns (patterns/) → pages (pages/). Pages register themselves by
// convention: every viz/pages/*.js module exports { id, render(ui) } and is
// picked up by the startup scan below — adding a page never edits this file.
//
// Paso 3 (manifiestos): a page also exports `manifest` — its machine-checkable
// contract: { consumes: 'rows'|'object', overridable: [param, …] }.
// validateSpec() does the matchmaking (manifest vs the source's `emits` and
// args) so an invalid spec is rejected at creation and an unknown component
// (version skew: a spec ahead of this fork's genome) degrades gracefully
// instead of rendering garbage.
//
// This module keeps the pre-split public interface (renderPane + the
// SSE-addressable block fragments + table/escape) so server.js and html.js
// are untouched by the partition.

const fs = require("node:fs");
const path = require("node:path");
const { table, escape } = require("./kit");
const { SOURCES } = require("./datasources");
const { renderTaskDetail } = require("../blocks/task-detail");
const { renderTaskEditForm, renderSqlPreview } = require("../blocks/task-edit-form");
const { renderMeetingDetail } = require("../blocks/meeting-detail");

const PAGES_DIR = path.join(__dirname, "..", "pages");

// id → page module. Fails loudly at startup on a malformed or duplicate page —
// a broken registry should never boot half-silent.
const PAGES = new Map();
for (const f of fs.readdirSync(PAGES_DIR).filter((f) => f.endsWith(".js")).sort()) {
  const mod = require(path.join(PAGES_DIR, f));
  if (!mod || typeof mod.render !== "function" || !mod.id) {
    throw new Error(`Página inválida en pages/${f}: debe exportar { id, render }`);
  }
  if (PAGES.has(mod.id)) throw new Error(`Página duplicada: "${mod.id}" (pages/${f})`);
  PAGES.set(mod.id, mod);
}

function listPages() {
  return [...PAGES.keys()];
}

// The manifest of a component ('' / unknown → the generic table's), or null.
function getManifest(componentId) {
  const page = PAGES.get(componentId || "table");
  return (page && page.manifest) || null;
}

// Validate one UI spec against the registry + SOURCES: component exists,
// source exists, the source's `emits` matches the page's `consumes`, and every
// param is either a whitelisted source arg or declared `overridable` by the
// page. Unknown params on an already-saved spec are a *warning*, not an error
// (old specs must keep rendering); the create form treats warnings as errors.
function validateSpec(spec) {
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
// Empty component falls through to the generic `table` page (original
// semantics); an *unknown* component degrades gracefully (version skew).
function renderPane(ui) {
  if (!ui) {
    return `<section id="pane" class="flex-1 p-8">
      <div class="h-full flex items-center justify-center text-slate-400">
        <p>Selecciona una UI en el panel izquierdo, o crea una nueva.</p>
      </div></section>`;
  }
  if (ui.component && !PAGES.has(ui.component)) {
    return degradeCard(ui, validateSpec(ui).errors);
  }
  const page = PAGES.get(ui.component || "table");
  return page.render(ui);
}

module.exports = {
  renderPane,
  listPages,
  getManifest,
  validateSpec,
  renderTaskDetail,
  renderTaskEditForm,
  renderMeetingDetail,
  renderSqlPreview,
  table,
  escape,
};
