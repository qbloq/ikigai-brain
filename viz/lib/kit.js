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
// Wears the design system's `.table-wrap > .table-scroll > table.tbl` (see
// public/tokens.css): sticky uppercase micro headers, hairline rules, hover on
// --brand-soft. The DS owns the look; what stays in utilities is LAYOUT, which
// no theme has an opinion about — in particular the width floor, which lives on
// the CELLS (`min-w-*` + nowrap headers) because the column count is arbitrary
// here: their minimums add up to the table's min-content width, so a narrow
// container makes the wrapper scroll horizontally instead of compressing every
// column. Cell text still wraps — nothing is hidden.
function table(rows) {
  if (!rows.length) {
    return '<p class="text-slate-500 italic">Sin resultados.</p>';
  }
  const cols = inferColumns(rows);
  const thead = cols.map((c) => `<th>${escape(c)}</th>`).join("");
  const tbody = rows
    .map((r) => `<tr>${cols.map((c) => `<td class="align-top min-w-[7rem]">${cell(r[c])}</td>`).join("")}</tr>`)
    .join("");
  return `<div class="table-wrap"><div class="table-scroll overflow-y-auto max-h-[calc(100vh-9rem)]"><table class="tbl">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div></div>`;
}

// Compact table for in-panel previews: the DS's `.dense` modifier, nowrap cells
// (the wrapper scrolls both axes), truncated long values.
function miniTable(rows) {
  if (!rows.length) return '<p class="text-xs text-slate-400 italic p-2">Sin resultados.</p>';
  const cols = inferColumns(rows);
  const thead = cols.map((c) => `<th>${escape(c)}</th>`).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr>${cols
          .map((c) => `<td class="whitespace-nowrap max-w-[16rem] overflow-hidden text-ellipsis">${cell(r[c])}</td>`)
          .join("")}</tr>`
    )
    .join("");
  return `<table class="tbl dense"><thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table>`;
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
// The DS's `.select` (chevron, focus ring, themed surface). It is width:100% by
// design — a filter bar wants intrinsic width, and `w-auto` overrides it because
// Tailwind's utilities land after tokens.css in the cascade.
function selectCtl(signal, current, options, reget, indicator = "loadingtasks") {
  const opts = options
    .map(([v, l]) => `<option value="${escape(v)}"${String(v) === String(current) ? " selected" : ""}>${escape(l)}</option>`)
    .join("");
  return `<select data-bind="${signal}" data-on:change="${reget}" data-indicator:${indicator}
    class="select w-auto">${opts}</select>`;
}

// El gemelo de selectCtl para un checkbox. Existe porque el `.check` del DS no
// es un input pelado: esconde el nativo y dibuja su propia caja (`.box` + el
// SVG del palomito), que es lo que le permite tomar color del tema. Un
// `<input type=checkbox>` nativo se queda con el look del sistema operativo y
// en tema oscuro aparece como un cuadro claro que no pertenece a nada.
//
// Seis bloques repetían el mismo markup, así que vive en el kernel — pero
// crecer kit.js es decisión de gobernanza (viz/CLAUDE.md), no conveniencia:
// queda anotado como el segundo control de formulario del kit, hermano de
// selectCtl y con la misma firma.
const CHECK_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';

// `value` convierte al control en parte de un MULTISELECT: varios checkboxes
// con la misma señal, predefinida como array, acumulan en ella sus values
// (Datastar 1.0, data-bind > predefined signal types). Sin `value` sigue siendo
// el booleano de siempre.
// `mods` son modificadores de Datastar para el evento (p.ej. "__debounce.50ms").
// Importa cuando el handler dispara una petición que LEE la señal que este mismo
// control acaba de cambiar: sin diferir, `change` puede correr antes de que
// `data-bind` haya escrito, y la petición viaja con el valor viejo — la fila se
// re-renderiza con el estado anterior y la casilla «rebota».
function checkCtl(
  signal,
  label,
  on,
  { indicator = "loadingtasks", checked = false, id = "", cls = "", value = null, mods = "" } = {}
) {
  return `<label class="check px-2 ${cls}">
      <input type="checkbox"${id ? ` id="${escape(id)}"` : ""} data-bind="${signal}"${
        value !== null ? ` value="${escape(value)}"` : ""
      }${checked ? " checked" : ""}${on ? ` data-on:change${mods}="${on}"` : ""}${
        indicator ? ` data-indicator:${indicator}` : ""
      } />
      <span class="box">${CHECK_SVG}</span>
      ${escape(label)}
    </label>`;
}

// Titled section for detail panels (uppercase label + optional count).
function section(title, count, inner) {
  return `<div class="mb-5">
    <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2" style="letter-spacing:var(--tr-micro)">${escape(title)}${count != null ? ` · ${count}` : ""}</h3>
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
  checkCtl,
  section,
  PRIORITY_DOT,
  priorityDot,
  dueFmt,
};
