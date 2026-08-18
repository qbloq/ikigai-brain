// charts-init — client glue for the vendored Chart.js bundle (/chart.umd.js).
// The server renders declarative placeholders (<div data-chart='{spec}'>, see
// viz/blocks/charts.js) and this file instantiates them: on first load and —
// via a MutationObserver — after every Datastar SSE patch, so charts survive
// idiomorph morphs without per-page wiring. Split of responsibilities: the
// server owns the DATA (a compact spec: kind/labels/series), this file owns
// the DRAWING (palette, mark specs, tooltips) — each decision lives in one place.
//
// Palette: every color is READ FROM CSS at draw time (tokens.css), so a chart
// follows the client's theme and the light/dark toggle like the rest of the UI.
// The hex below are only the fallbacks for a page served without tokens.css.
//
// Two different kinds of color live here, and they are governed differently:
//
//   · CHROME (grid, axis, ink, surface, tooltip) is THEMED. It has to be — a
//     #ffffff card surface and a near-white gridline are simply wrong on a
//     dark background, which is the bug this replaces.
//   · The CATEGORICAL SLOTS are NOT branded by default. They stay the dataviz
//     reference set, validated with the skill's six-checks script (worst
//     adjacent CVD ΔE 24.2; aqua/yellow/magenta are sub-3:1 on white → the
//     chart page ships a table view as relief). The slot ORDER is the
//     CVD-safety mechanism — never reorder, never cycle past 8. A theme *can*
//     override --chart-1..8, but that is a deliberate accessibility decision:
//     the DS's brand ramp (--c-1..--c-6) is not CVD-validated, so it is not
//     wired in by default.

const FALLBACK = {
  slots: ["#2a78d6", "#1baf7a", "#eda100", "#008300", "#4a3aa7", "#e34948", "#e87ba4", "#eb6834"],
  other: "#898781", // the «Otros» fold — neutral, deliberately not an identity hue
  muted: "#898781", // axis/tick ink
  ink2: "#52514e", // legend ink
  grid: "#e1e0d9", // hairline gridlines (solid, never dashed)
  axis: "#c3c2b7", // baseline/axis rule
  surface: "#ffffff", // card surface — the 2px gap/ring color
  tipBg: "rgba(11,11,11,0.92)",
  tipTitle: "#c3c2b7",
  tipBody: "#ffffff",
};

// Resolved palette. Repopulated at boot and whenever the theme flips; the
// getters below always read through it, never a captured constant.
let C = { ...FALLBACK };

function cssVar(name, fallback) {
  const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return v || fallback;
}

function readPalette() {
  C = {
    slots: FALLBACK.slots.map((hex, i) => cssVar(`--chart-${i + 1}`, hex)),
    other: cssVar("--chart-other", FALLBACK.other),
    muted: cssVar("--axis-text", FALLBACK.muted),
    ink2: cssVar("--text-2", FALLBACK.ink2),
    grid: cssVar("--grid-line", FALLBACK.grid),
    axis: cssVar("--border-2", FALLBACK.axis),
    surface: cssVar("--surface-2", FALLBACK.surface),
    tipBg: cssVar("--tip-bg", FALLBACK.tipBg),
    tipTitle: cssVar("--tip-title", FALLBACK.tipTitle),
    tipBody: cssVar("--tip-body", FALLBACK.tipBody),
  };
}

// Alfa sobre un color de la paleta. Los slots son hex (concatenar "d9" basta),
// pero un tema podría declarar rgb()/color-mix() — de ahí el color-mix de rescate.
function alpha(c, hexSuffix, pct) {
  return /^#[0-9a-fA-F]{6}$/.test(c) ? c + hexSuffix : `color-mix(in srgb, ${c} ${pct}%, transparent)`;
}

function fmt(n) {
  return Number(n).toLocaleString("en-US");
}

function legend(display, position = "bottom") {
  return { display, position, labels: { color: C.ink2, usePointStyle: true, boxWidth: 8, boxHeight: 8, padding: 14 } };
}

// Canvas-drawn tooltip (no DOM/HTML → labels can't inject markup).
function tooltip(extra) {
  return Object.assign(
    {
      backgroundColor: C.tipBg,
      titleColor: C.tipTitle,
      bodyColor: C.tipBody,
      padding: 10,
      cornerRadius: 8,
      boxPadding: 4,
      usePointStyle: true,
      callbacks: {
        label(c) {
          const v = typeof c.parsed === "number" ? c.parsed : c.chart.options.indexAxis === "y" ? c.parsed.x : c.parsed.y;
          return ` ${c.dataset.label ? c.dataset.label + ": " : ""}${fmt(v)}`;
        },
      },
    },
    extra || {}
  );
}

const valueScale = () => ({
  beginAtZero: true,
  grid: { color: C.grid },
  border: { color: C.axis },
  ticks: { color: C.muted, precision: 0, callback: (v) => fmt(v) },
});
const catScale = () => ({ grid: { display: false }, border: { color: C.axis }, ticks: { color: C.muted, autoSkip: false } });

// Bars: single series → ONE color for every bar (identity is on the axis; a
// hue per bar is the value-ramp/rainbow anti-pattern). ≤24px thick, 4px
// rounded data-end, square at the baseline. Horizontal by default — long
// Spanish category names read better on the y axis.
function barConfig(spec) {
  const single = (spec.series || []).length <= 1;
  const horizontal = spec.horizontal !== false;
  const datasets = (spec.series || []).map((s, i) => {
    const c = single ? C.slots[0] : C.slots[i % C.slots.length];
    return {
      label: s.label || "",
      data: s.data,
      backgroundColor: c,
      hoverBackgroundColor: alpha(c, "d9", 85),
      maxBarThickness: 24,
      borderRadius: 4,
      borderSkipped: "start",
    };
  });
  return {
    type: "bar",
    data: { labels: spec.labels, datasets },
    options: {
      indexAxis: horizontal ? "y" : "x",
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 400 },
      scales: horizontal ? { x: valueScale(), y: catScale() } : { x: catScale(), y: valueScale() },
      plugins: { legend: legend(!single), tooltip: tooltip() },
    },
  };
}

// Donut: part-to-whole only, ≤6 segments (the server folds the tail into
// «Otros», which wears neutral gray — never an identity hue). The 2px white
// border IS the surface gap between slices. Legend = the identity channel.
function donutConfig(spec) {
  const s0 = (spec.series || [])[0] || { data: [] };
  const colors = spec.labels.map((_, i) => (i === spec.otherIndex ? C.other : C.slots[i % C.slots.length]));
  return {
    type: "doughnut",
    data: {
      labels: spec.labels,
      datasets: [
        {
          label: s0.label || "",
          data: s0.data,
          backgroundColor: colors,
          hoverBackgroundColor: colors.map((c) => alpha(c, "d9", 85)),
          borderColor: C.surface,
          borderWidth: 2,
          hoverOffset: 4,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      cutout: "62%",
      animation: { duration: 400 },
      plugins: {
        legend: legend(true, "right"),
        tooltip: tooltip({
          callbacks: {
            label(c) {
              const total = c.dataset.data.reduce((s, v) => s + (Number(v) || 0), 0);
              const pct = total ? Math.round((c.parsed / total) * 100) : 0;
              return ` ${c.label}: ${fmt(c.parsed)} (${pct}%)`;
            },
          },
        }),
      },
    },
  };
}

// Line: 2px stroke, ≥8px markers with a 2px surface ring, area fill only as a
// ~10% wash. One tooltip lists every series at the hovered X (mode: index).
function lineConfig(spec) {
  const multi = (spec.series || []).length > 1;
  const datasets = (spec.series || []).map((s, i) => {
    const c = C.slots[i % C.slots.length];
    return {
      label: s.label || "",
      data: s.data,
      borderColor: c,
      borderWidth: 2,
      tension: 0.15,
      pointRadius: 4,
      pointHoverRadius: 6,
      pointBackgroundColor: c,
      pointBorderColor: C.surface,
      pointBorderWidth: 2,
      backgroundColor: alpha(c, "1a", 10),
      fill: !multi && spec.fill === true,
    };
  });
  return {
    type: "line",
    data: { labels: spec.labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 400 },
      interaction: { mode: "index", intersect: false },
      scales: { x: catScale(), y: valueScale() },
      plugins: { legend: legend(multi), tooltip: tooltip() },
    },
  };
}

function buildConfig(spec) {
  if (spec.kind === "donut") return donutConfig(spec);
  if (spec.kind === "line") return lineConfig(spec);
  return barConfig(spec);
}

function initChart(el) {
  if (!window.Chart) return;
  const json = el.getAttribute("data-chart");
  if (!json) return;
  let canvas = el.querySelector("canvas");
  // Healthy instance with an unchanged spec → keep it (no re-animation when an
  // unrelated morph touches the pane).
  const healthy = el.__chart && canvas && el.__chart.canvas === canvas && canvas.getAttribute("width");
  if (json === el.__chartJson && healthy) return;
  let spec;
  try {
    spec = JSON.parse(json);
  } catch {
    return;
  }
  if (el.__chart) {
    try {
      el.__chart.destroy();
    } catch {
      /* already gone */
    }
    el.__chart = null;
  }
  if (canvas) {
    const prev = Chart.getChart(canvas);
    if (prev) prev.destroy();
  } else {
    canvas = document.createElement("canvas");
    el.appendChild(canvas);
  }
  el.__chartJson = json;
  el.__chart = new Chart(canvas, buildConfig(spec));
}

// idiomorph syncs attributes to the server's HTML, so a same-spec repatch can
// strip the width/height Chart.js put on the canvas → watch for that (a bare
// canvas inside a chart host) and rebuild. No loop: once Chart.js re-sets
// width, the guard in initChart short-circuits.
function onMutations(muts) {
  for (const m of muts) {
    if (m.type === "attributes") {
      const el = m.target;
      if (el.nodeType !== 1) continue;
      if (el.hasAttribute("data-chart")) initChart(el);
      else if (el.tagName === "CANVAS" && !el.getAttribute("width")) {
        const host = el.closest("[data-chart]");
        if (host) {
          host.__chartJson = null;
          initChart(host);
        }
      }
    } else {
      for (const n of m.addedNodes) {
        if (n.nodeType !== 1) continue;
        if (n.hasAttribute && n.hasAttribute("data-chart")) initChart(n);
        if (n.querySelectorAll) n.querySelectorAll("[data-chart]").forEach(initChart);
      }
      const host = m.target && m.target.closest ? m.target.closest("[data-chart]") : null;
      if (host) initChart(host);
    }
  }
}

// Chart.js keeps colors as strings, not live CSS — so flipping the theme has
// to re-read the palette and rebuild. Clearing __chartJson defeats initChart's
// same-spec guard; the data never leaves the DOM, so nothing is re-fetched.
function repaint() {
  readPalette();
  Chart.defaults.color = C.muted;
  Chart.defaults.font.family = cssVar("--font-ui", 'system-ui, -apple-system, "Segoe UI", sans-serif');
  document.querySelectorAll("[data-chart]").forEach((el) => {
    el.__chartJson = null;
    initChart(el);
  });
}

function boot() {
  readPalette();
  Chart.defaults.font.family = cssVar("--font-ui", 'system-ui, -apple-system, "Segoe UI", sans-serif');
  Chart.defaults.font.size = 12;
  Chart.defaults.color = C.muted;
  document.querySelectorAll("[data-chart]").forEach(initChart);
  new MutationObserver(onMutations).observe(document.body, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["data-chart", "width"],
  });
  new MutationObserver(repaint).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["data-theme"],
  });
}

// chart.umd.js loads as a deferred classic script before this module in
// document order, but guard anyway.
if (window.Chart) boot();
else {
  let tries = 0;
  const t = setInterval(() => {
    if (window.Chart) {
      clearInterval(t);
      boot();
    } else if (++tries > 200) clearInterval(t);
  }, 25);
}
