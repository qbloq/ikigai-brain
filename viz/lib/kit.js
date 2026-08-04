// kit — the viz kernel (KIT_VERSION 1): the small, deliberately stable set of
// primitives every block/pattern/page builds on — HTML escaping, generic
// tables, form controls, panel sections, and the shared domain formatters
// (priority dot, due date). Nothing here fetches data, owns a route, or knows
// which component is calling. Growing or changing this file is a governance
// decision, not a convenience: independently-authored components compose only
// because this contract stays small and stable (docs/deltas-architecture.md).

const KIT_VERSION = 1;

function escape(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function inferColumns(rows) {
  const seen = [];
  for (const r of rows) {
    if (r && typeof r === "object") {
      for (const k of Object.keys(r)) if (!seen.includes(k)) seen.push(k);
    }
  }
  return seen;
}

function cell(v) {
  if (v == null || v === "") return '<span class="text-slate-400">—</span>';
  if (Array.isArray(v)) return escape(v.join(", "));
  if (typeof v === "object") return escape(JSON.stringify(v));
  return escape(v);
}

// Generic table with inferred columns (union of keys, first-seen order).
function table(rows) {
  if (!rows.length) {
    return '<p class="text-slate-500 italic">Sin resultados.</p>';
  }
  const cols = inferColumns(rows);
  const thead = cols
    .map(
      (c) =>
        `<th class="text-left font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c)}</th>`
    )
    .join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr class="even:bg-slate-50/60 hover:bg-indigo-50">${cols
          .map((c) => `<td class="px-3 py-2 border-b border-slate-100 align-top">${cell(r[c])}</td>`)
          .join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-9rem)]"><table class="w-full text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

// Compact table for in-panel previews: tiny type, nowrap cells (the wrapper
// scrolls both axes), truncated long values.
function miniTable(rows) {
  if (!rows.length) return '<p class="text-[11px] text-slate-400 italic p-2">Sin resultados.</p>';
  const cols = inferColumns(rows);
  const thead = cols
    .map((c) => `<th class="text-left font-semibold px-2 py-1 border-b border-slate-200 sticky top-0 bg-slate-50 whitespace-nowrap">${escape(c)}</th>`)
    .join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr class="even:bg-slate-50/60">${cols
          .map((c) => `<td class="px-2 py-1 border-b border-slate-100 whitespace-nowrap max-w-[16rem] overflow-hidden text-ellipsis">${cell(r[c])}</td>`)
          .join("")}</tr>`
    )
    .join("");
  return `<table class="text-[11px] border-collapse"><thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table>`;
}

// Ordered group-by: keys keep first-seen order.
function groupBy(rows, keyFn) {
  const order = [];
  const map = new Map();
  for (const r of rows) {
    const k = keyFn(r);
    if (!map.has(k)) {
      map.set(k, []);
      order.push(k);
    }
    map.get(k).push(r);
  }
  return order.map((k) => [k, map.get(k)]);
}

// Distinct values across rows (flattening array-valued fields), es-collated.
function distinct(rows, pick) {
  const set = new Set();
  for (const r of rows) {
    const v = pick(r);
    if (Array.isArray(v)) v.forEach((x) => x && set.add(x));
    else if (v) set.add(v);
  }
  return [...set].sort((a, b) => a.localeCompare(b, "es"));
}

// JS string literal for embedding a value inside a data-show expression (single
// quotes; the attribute itself is double-quoted, so escape only single quotes).
function jsStr(v) {
  return "'" + String(v ?? "").replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'";
}
function jsArr(arr) {
  return "[" + (arr || []).map(jsStr).join(",") + "]";
}

// A filter <select> bound to a Datastar signal that re-fetches on change.
// `indicator` is the loading-overlay signal the fetch drives.
function selectCtl(signal, current, options, reget, indicator = "loadingtasks") {
  const opts = options
    .map(([v, l]) => `<option value="${escape(v)}"${String(v) === String(current) ? " selected" : ""}>${escape(l)}</option>`)
    .join("");
  return `<select data-bind="${signal}" data-on:change="${reget}" data-indicator:${indicator}
    class="text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400">${opts}</select>`;
}

// Titled section for detail panels (uppercase label + optional count).
function section(title, count, inner) {
  return `<div class="mb-5">
    <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">${escape(title)}${count != null ? ` · ${count}` : ""}</h3>
    ${inner}
  </div>`;
}

// Shared task-domain formatters (used by task tables, detail panels and the
// meeting report's action items).
const PRIORITY_DOT = {
  High: { c: "bg-red-500", t: "Alta" },
  Medium: { c: "bg-amber-400", t: "Media" },
  Low: { c: "bg-emerald-500", t: "Baja" },
};
const MESES = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"];

function priorityDot(v) {
  const d = PRIORITY_DOT[v];
  if (!d) return cell(v);
  return `<span class="inline-block w-2.5 h-2.5 rounded-full ${d.c}" title="${escape(d.t)}"></span>`;
}

function dueFmt(v) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v ?? ""));
  if (!m) return cell(v);
  const mon = MESES[Number(m[2]) - 1] || m[2];
  return `${mon} ${Number(m[3])}`;
}

module.exports = {
  KIT_VERSION,
  escape,
  inferColumns,
  cell,
  table,
  miniTable,
  groupBy,
  distinct,
  jsStr,
  jsArr,
  selectCtl,
  section,
  PRIORITY_DOT,
  priorityDot,
  dueFmt,
};
