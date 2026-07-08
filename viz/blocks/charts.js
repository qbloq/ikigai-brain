// charts block — the server side of the chart system: shapes tabular rows into
// a compact chart spec ({kind, labels, series}) and emits the declarative
// placeholder that public/charts-init.js (the client glue) instantiates with
// the vendored Chart.js. The block owns the DATA shaping (pick columns, sort,
// fold the donut tail into «Otros»); the glue owns the DRAWING (palette, mark
// specs, tooltips) — each decision lives in one place.

const { escape, inferColumns } = require("../lib/kit");

const isNum = (v) => v != null && v !== "" && !Number.isNaN(Number(v));

// rows → spec. Columns: x = the label column (first with non-numeric values),
// y = the value column (first numeric, ≠ x); both overridable. Bars/donas sort
// by value desc (magnitude comparison); lines keep source order (usually time).
// Donuts cap at 6 segments — the tail folds into «Otros», flagged via
// otherIndex so the glue paints it neutral gray instead of an identity hue.
function rowsToSpec(rows, { kind = "bar", x, y, seriesLabel, sort } = {}) {
  if (!rows || !rows.length) return null;
  const cols = inferColumns(rows);
  const xCol = x && cols.includes(x) ? x : cols.find((c) => rows.some((r) => !isNum(r[c]))) || cols[0];
  const yCol = y && cols.includes(y) ? y : cols.find((c) => c !== xCol && rows.some((r) => isNum(r[c])));
  if (!xCol || !yCol) return null;

  let pairs = rows.map((r) => [r[xCol] == null || r[xCol] === "" ? "—" : String(r[xCol]), isNum(r[yCol]) ? Number(r[yCol]) : 0]);
  if (sort !== "none" && kind !== "line") pairs = [...pairs].sort((a, b) => b[1] - a[1]);

  let otherIndex;
  if (kind === "donut" && pairs.length > 6) {
    const rest = pairs.slice(5);
    pairs = pairs.slice(0, 5);
    pairs.push([`Otros (${rest.length})`, rest.reduce((s, p) => s + p[1], 0)]);
    otherIndex = 5;
  }

  const spec = {
    kind,
    labels: pairs.map((p) => p[0]),
    series: [{ label: seriesLabel || yCol, data: pairs.map((p) => p[1]) }],
  };
  if (otherIndex != null) spec.otherIndex = otherIndex;
  return spec;
}

// The placeholder the glue picks up (initial load + after SSE patches). The
// wrapper fixes the height (bars grow with category count so the axis band is
// never clipped); Chart.js fills it via maintainAspectRatio: false.
function chartEl(spec, { height } = {}) {
  if (!spec) return '<p class="text-slate-500 italic">Sin datos para graficar.</p>';
  const h =
    height ||
    (spec.kind === "donut" ? 300 : spec.kind === "line" ? 320 : Math.min(560, Math.max(220, spec.labels.length * 34 + 56)));
  return `<div class="relative" style="height:${h}px" data-chart="${escape(JSON.stringify(spec))}"><canvas></canvas></div>`;
}

module.exports = { rowsToSpec, chartEl };
