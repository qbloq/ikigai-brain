// master-detail pattern — the first named (and now GENERALIZED) pattern of the
// composition tower: a filterable master list on the left and an SSE-patched
// detail panel that slides in on row click.
//
// The pattern OWNS the wiring — that's what makes it a pattern and not a
// template (docs/deltas-architecture.md): the layout, the detail-panel
// open/close animation, the loading overlays, the selection signals, the
// row-click → /c/<detail>/frag/<frag> route, and the filter → @get re-fetch.
// None of that is declarable; a spec only fills the SLOTS:
//
//   master: { block, source, params? }   block = master-contract module
//     (signals / regetQS / controls / prepare? / table / counter / headerExtra)
//   detail: { block, frag? }             block = routed detail block
//     (manifest: { slot:'detail', frag, width, selSignal } + frags)
//
// Instances: pages `tasks` and `task-editor` (same master, different detail
// block) and `meetings` (its own master block) — plus any spec_version 2
// record: { pattern: "master-detail", master: {...}, detail: {...} }, where
// the blocks are resolved by id from the component registry.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

function render(ui, slots) {
  const master = slots.master;
  const detail = slots.detail;
  const mb = master.block;
  const db = detail.block;
  const dm = db.manifest || {};
  const frag = detail.frag || dm.frag || "panel";
  const sel = dm.selSignal || "selected";
  const width = dm.width || "24rem";
  const indicator = (mb.manifest && mb.manifest.indicator) || "loadingmaster";

  // v2 specs may carry base params in the master slot; runtime overrides
  // (withParamOverrides) ride ui.params on top.
  const p = { ...(master.params || {}), ...(ui.params || {}) };

  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    ${mb.headerExtra || ""}
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  let rows = [],
    err;
  try {
    ({ rows } = fetchSource(master.source, p));
  } catch (e) {
    err = e.message;
  }
  if (mb.prepare) rows = mb.prepare(rows, p);

  const reget = `@get('/ui/${escape(ui.id)}?'+${mb.regetQS})`;
  const controls = `<div class="flex flex-wrap items-center gap-2 mb-4" data-signals="${escape(JSON.stringify(mb.signals(p)))}">
    ${mb.controls(p, reget)}
  </div>`;

  // The pattern's wiring, handed to the master block's table: row click opens
  // the detail block's frag (canonical /c/… route) and marks the selection.
  const wire = {
    rowAttrs: (r) =>
      `data-on:click="$${sel}='${escape(r.id)}'; $detailOpen=true; @get('/c/${db.id}/frag/${frag}?id=${escape(r.id)}')" ` +
      `data-indicator:loading data-class:row-sel="$${sel}==='${escape(r.id)}'"`,
    sort: mb.sortState ? { ...mb.sortState(p), reget } : null,
  };

  const body = err
    ? `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>`
    : `<div class="relative">
        <div id="master-loading" data-class:on="$${indicator}" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
          <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
        </div>
        <p class="text-xs text-slate-400 mb-2">${mb.counter ? mb.counter(rows.length) : `${rows.length} fila(s)`}</p>${mb.table(rows, wire)}
      </div>`;

  // The detail panel seeds with the frag's own empty state (same handler the
  // row click hits, with no id). #detail-wrap PERSISTS (never replaced by SSE)
  // so its width/opacity transition fires every open/close; only its inner
  // fragment is swapped by the /c/<detail>/frag route. Closed by default; the
  // .is-open class (base CSS = closed) avoids a Tailwind width conflict and a
  // load-time flash. `detailOpen` lives on #pane, which resets on filter.
  const emptyPanel = db.frags[frag]({ params: new URLSearchParams() });

  return `<section id="pane" class="flex-1 overflow-hidden flex" data-signals="${escape(JSON.stringify({ detailOpen: false, [sel]: "" }))}">
    <style>
      #detail-wrap{width:0;opacity:0;overflow:hidden;transition:width .3s ease-in-out,opacity .3s ease-in-out;}
      #detail-wrap.is-open{width:${width};opacity:1;border-left:1px solid rgb(226 232 240);}
      #detail-loading,#master-loading{opacity:0;transition:opacity .2s ease;}
      #detail-loading.on,#master-loading.on{opacity:1;}
      tr.row-sel{background:rgb(238 242 255)!important;box-shadow:inset 3px 0 0 rgb(79 70 229);}
    </style>
    <div class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${body}</div>
    <aside id="detail-wrap" data-class:is-open="$detailOpen" class="relative shrink-0 bg-white">
      <div id="detail-loading" data-class:on="$loading" class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center bg-white/50">
        <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
      </div>
      ${emptyPanel}
    </aside>
  </section>`;
}

module.exports = {
  id: "master-detail",
  // Slot contract for validateSpec (v2): what each slot must be filled with.
  manifest: {
    slots: {
      master: { slot: "master", consumes: "rows" },
      detail: { slot: "detail" },
    },
  },
  render,
};
