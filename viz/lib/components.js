// Component registry — the assembly point of the composition tower
// (docs/deltas-architecture.md): kernel (lib/kit.js) → blocks (blocks/) →
// patterns (patterns/) → pages (pages/). Pages register themselves by
// convention: every viz/pages/*.js module exports { id, render(ui) } and is
// picked up by the startup scan below — adding a page never edits this file.
//
// This module keeps the pre-split public interface (renderPane + the
// SSE-addressable block fragments + table/escape) so server.js and html.js
// are untouched by the partition.

const fs = require("node:fs");
const path = require("node:path");
const { table, escape } = require("./kit");
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

// Render a saved UI spec into the pane HTML (a #pane element, id-matched by SSE).
// Unknown/empty components fall through to the generic `table` page, which
// preserves the original semantics (table for "table"/empty, <pre> otherwise).
function renderPane(ui) {
  if (!ui) {
    return `<section id="pane" class="flex-1 p-8">
      <div class="h-full flex items-center justify-center text-slate-400">
        <p>Selecciona una UI en el panel izquierdo, o crea una nueva.</p>
      </div></section>`;
  }
  const page = PAGES.get(ui.component) || PAGES.get("table");
  return page.render(ui);
}

module.exports = { renderPane, listPages, renderTaskDetail, renderTaskEditForm, renderMeetingDetail, renderSqlPreview, table, escape };
