// charts-init — client glue for the vendored Chart.js bundle (/chart.umd.js).
// The server renders declarative placeholders (<div data-chart='{spec}'>, see
// viz/blocks/charts.js) and this file instantiates them: on first load and —
// via a MutationObserver — after every Datastar SSE patch, so charts survive
// idiomorph morphs without per-page wiring. Split of responsibilities: the
// server owns the DATA (a compact spec: kind/labels/series), this file owns
// the DRAWING (palette, mark specs, tooltips) — each decision lives in one place.
//
// Palette: the dataviz reference categorical set, validated with the skill's
// six-checks script (worst adjacent CVD ΔE 24.2; aqua/yellow/magenta are
// sub-3:1 on white → the chart page ships a table view as relief). The slot
// ORDER is the CVD-safety mechanism — never reorder, never cycle past 8.

const SLOTS = ["#2a78d6", "#1baf7a", "#eda100", "#008300", "#4a3aa7", "#e34948", "#e87ba4", "#eb6834"];
const OTHER = "#898781"; // the «Otros» fold — neutral, deliberately not an identity hue
const MUTED = "#898781"; // axis/tick ink
const INK2 = "#52514e"; // legend ink
const GRID = "#e1e0d9"; // hairline gridlines (solid, never dashed)
const AXIS = "#c3c2b7"; // baseline/axis rule
const SURFACE = "#ffffff"; // card surface — the 2px gap/ring color

function fmt(n) {
  return Number(n).toLocaleString("en-US");
}

function legend(display, position = "bottom") {
  return { display, position, labels: { color: INK2, usePointStyle: true, boxWidth: 8, boxHeight: 8, padding: 14 } };
}

// Canvas-drawn tooltip (no DOM/HTML → labels can't inject markup).
function tooltip(extra) {
  return Object.assign(
    {
      backgroundColor: "rgba(11,11,11,0.92)",
      titleColor: "#c3c2b7",
      bodyColor: "#ffffff",
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
  grid: { color: GRID },
  border: { color: AXIS },
  ticks: { color: MUTED, precision: 0, callback: (v) => fmt(v) },
});
const catScale = () => ({ grid: { display: false }, border: { color: AXIS }, ticks: { color: MUTED, autoSkip: false } });

// Bars: single series → ONE color for every bar (identity is on the axis; a
// hue per bar is the value-ramp/rainbow anti-pattern). ≤24px thick, 4px
// rounded data-end, square at the baseline. Horizontal by default — long
// Spanish category names read better on the y axis.
function barConfig(spec) {
  const single = (spec.series || []).length <= 1;
  const horizontal = spec.horizontal !== false;
  const datasets = (spec.series || []).map((s, i) => {
    const c = single ? SLOTS[0] : SLOTS[i % SLOTS.length];
    return {
      label: s.label || "",
      data: s.data,
      backgroundColor: c,
      hoverBackgroundColor: c + "d9",
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
  const colors = spec.labels.map((_, i) => (i === spec.otherIndex ? OTHER : SLOTS[i % SLOTS.length]));
  return {
    type: "doughnut",
    data: {
      labels: spec.labels,
      datasets: [
        {
          label: s0.label || "",
          data: s0.data,
          backgroundColor: colors,
          hoverBackgroundColor: colors.map((c) => c + "d9"),
          borderColor: SURFACE,
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
    const c = SLOTS[i % SLOTS.length];
    return {
      label: s.label || "",
      data: s.data,
      borderColor: c,
      borderWidth: 2,
      tension: 0.15,
      pointRadius: 4,
      pointHoverRadius: 6,
      pointBackgroundColor: c,
      pointBorderColor: SURFACE,
      pointBorderWidth: 2,
      backgroundColor: c + "1a",
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

function boot() {
  Chart.defaults.font.family = 'system-ui, -apple-system, "Segoe UI", sans-serif';
  Chart.defaults.font.size = 12;
  Chart.defaults.color = MUTED;
  document.querySelectorAll("[data-chart]").forEach(initChart);
  new MutationObserver(onMutations).observe(document.body, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["data-chart", "width"],
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
