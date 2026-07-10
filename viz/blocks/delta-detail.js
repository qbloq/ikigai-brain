// delta-detail block (#delta-detail) — the DETAIL slot of the Cola de
// Gobernanza (docs/torre-de-control.md, T3): the digest of ONE delta from the
// `fleet_delta` source, plus THE FIRST WRITE PATH of the torre — the three
// governance actions (Elevar / Pedir cambios / Descartar), each one @post →
// bash/fleet/review.sh (declared in manifest.writes; ctx.run enforces it).
//
// The heart of "on-rails": a ui-spec delta is approved by SEEING it — the
// panel embeds a shadow render (an isolated iframe onto /shadow/<key>, the
// spec straight from the fork, never installed) — while código/esquema show a
// diffstat and can only be dismissed or sent back (elevation of code goes
// through the engineering lane, not a button).

const { fetchSource } = require("../lib/datasources");
const { escape, section } = require("../lib/kit");

const REVIEW_SCRIPT = "bash/fleet/review.sh";

const ACTION_ES = {
  elevated: ["Elevada", "bg-emerald-100 text-emerald-700"],
  changes_requested: ["Cambios pedidos", "bg-amber-100 text-amber-700"],
  dismissed: ["Descartada", "bg-slate-200 text-slate-600"],
};

function panelShell(inner) {
  return `<div id="delta-detail" class="w-[34rem] h-full overflow-y-auto">${inner}</div>`;
}

function deltaDetailEmpty() {
  return panelShell(
    `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
      <p>Selecciona un delta para revisarlo.</p>
    </div>`
  );
}

function metaRow(label, value) {
  if (!value) return "";
  return `<div class="flex gap-2 text-xs"><span class="w-20 shrink-0 text-slate-400">${escape(label)}</span><span class="text-slate-700 font-mono break-all">${escape(value)}</span></div>`;
}

function decisionCard(d) {
  const [label, cls] = ACTION_ES[d.action] || [d.action, "bg-slate-100 text-slate-600"];
  return `<div class="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
    <p class="text-xs"><span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${cls}">${escape(label)}</span>
      <span class="text-slate-400 ml-1">${escape(d.ts || "")} · ${escape(d.by || "")}</span></p>
    ${d.to ? `<p class="text-xs text-slate-500 mt-1">→ ${escape(d.to)}</p>` : ""}
    ${d.reason ? `<p class="text-sm text-slate-700 mt-1">${escape(d.reason)}</p>` : ""}
    ${d.commit ? `<p class="text-[11px] text-slate-400 font-mono mt-1">commit ${escape(d.commit)}</p>` : ""}
  </div>`;
}

// Validation of the fork's spec against THIS genome — the same validateSpec
// that gates saved specs. Required lazily: components.js scans this blocks dir
// at boot, so a top-level require would be circular.
function specValidation(spec) {
  const { validateSpec } = require("../lib/components");
  const v = validateSpec(spec);
  if (v.ok && !v.warnings.length)
    return '<p class="text-xs text-emerald-600">✓ spec válida contra este genoma (componente, fuente y params whitelisted)</p>';
  const items = [...v.errors, ...v.warnings].map((e) => `<li>${escape(e)}</li>`).join("");
  return `<div class="rounded-lg border ${v.ok ? "border-amber-200 bg-amber-50 text-amber-700" : "border-red-200 bg-red-50 text-red-700"} p-2 text-xs">
    <ul class="list-disc list-inside space-y-0.5">${items}</ul></div>`;
}

function shadowBlock(d) {
  const src = `/shadow/${encodeURIComponent(d.key)}`;
  return `<div>
    <div class="flex items-baseline justify-between mb-1">
      <p class="text-[11px] font-semibold uppercase tracking-wide text-slate-400">Vista en sombra</p>
      <a href="${escape(src)}" target="_blank" class="text-xs text-indigo-600 hover:underline">abrir sombra ↗</a>
    </div>
    <iframe src="${escape(src)}" loading="lazy" title="Render en sombra de ${escape(d.slug || d.key)}"
      class="w-full h-96 rounded-lg border border-slate-200 pointer-events-none bg-white"></iframe>
    <p class="text-[11px] text-slate-400 mt-1">La spec del fork renderizada sobre datos vivos, sin instalarla — vista estática; los filtros solo operan en la sombra abierta.</p>
  </div>`;
}

function actionsBlock(d, note) {
  const base = `/c/delta-detail/act/review?id=${encodeURIComponent(d.key)}`;
  const canElevate = d.clase === "ui-spec";
  const btn = (label, action, cls, extra = "") =>
    `<button data-on:click="@post('${base}&action=${action}', {payload: {reason: $_dreason}})" data-indicator:loading ${extra}
      class="text-sm font-medium px-3 py-1.5 rounded-lg ${cls}">${label}</button>`;
  return `<div data-signals="${escape(JSON.stringify({ _dreason: "" }))}">
    ${note ? `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-2 text-xs mb-2">${escape(note)}</div>` : ""}
    <input data-bind="_dreason" placeholder="Razón de la decisión…"
      class="w-full text-sm border border-slate-300 rounded-lg px-3 py-1.5 mb-2 focus:outline-none focus:ring-1 focus:ring-indigo-400" />
    <div class="flex gap-2">
      ${canElevate ? btn("Elevar", "elevate", "bg-emerald-600 text-white hover:bg-emerald-700") : ""}
      ${btn("Pedir cambios", "changes", "bg-amber-100 text-amber-800 hover:bg-amber-200")}
      ${btn("Descartar", "dismiss", "bg-slate-100 text-slate-600 hover:bg-slate-200")}
    </div>
    ${canElevate ? "" : '<p class="text-[11px] text-slate-400 mt-1">Los deltas de código/esquema no se elevan con un botón: van por el carril de ingeniería.</p>'}
  </div>`;
}

function renderDeltaDetail(id, note) {
  if (!id) return deltaDetailEmpty();
  let d, err;
  try {
    const { rows } = fetchSource("fleet_delta", { id });
    d = rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err || !d) {
    return panelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(err || "Delta no encontrado")}</div></div>`
    );
  }
  const closeBtn = `<button data-on:click="$detailOpen=false; $selectedDelta=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>`;
  const header = `<div class="flex items-start gap-2 mb-1">${closeBtn}</div>
    <h2 class="text-base font-semibold text-slate-800 mb-1 -mt-6 pr-6">Δ ${escape(d.name || d.slug || d.path)}</h2>
    <p class="text-xs text-slate-500 mb-3">${escape(d.frontera)} · ${escape(d.clase)} · ${escape(d.employee)} (${escape(d.role || "?")})</p>`;

  const meta = `<div class="space-y-1 mb-3">
    ${metaRow("clave", d.key)}
    ${metaRow("path", d.path)}
    ${metaRow("fork", `${d.fork} @ ${d.fork_head}`)}
    ${metaRow("tocado", `${d.last_touch || "?"} (hace ${d.age_days ?? "?"}d)`)}
    ${d.spec && d.spec.derived_from ? metaRow("linaje", d.spec.derived_from) : ""}
  </div>`;

  let body = "";
  if (d.clase === "ui-spec" && d.spec) {
    body = `${section("Contrato de la spec", null, `<div class="space-y-1">
        ${metaRow("component", d.spec.component || (d.spec.pattern ? `pattern:${d.spec.pattern}` : "?"))}
        ${metaRow("source", d.spec.source || (d.spec.master && d.spec.master.source) || "?")}
        ${metaRow("params", JSON.stringify(d.spec.params || {}))}
      </div><div class="mt-2">${specValidation(d.spec)}</div>`)}
      ${shadowBlock(d)}`;
  } else if (d.diff) {
    body = section("Diff", null, `<pre class="text-xs bg-slate-50 border border-slate-200 rounded-lg p-3 overflow-x-auto whitespace-pre-wrap">${escape(d.diff)}</pre>`);
  }

  const decision = d.decided
    ? section("Decisión", null, decisionCard(d.decided))
    : section("Decidir", null, actionsBlock(d, note));

  const history =
    d.history && d.history.length
      ? section("Historial", d.history.length, `<div class="space-y-2">${d.history.map(decisionCard).join("")}</div>`)
      : "";

  return panelShell(`<div class="p-5">${header}${meta}${body ? `<div class="mb-3">${body}</div>` : ""}${decision}${history}</div>`);
}

const acts = {
  // POST /c/delta-detail/act/review?id=<key>&action=elevate|changes|dismiss
  // The reason travels as an explicit payload ({reason}), not as signals —
  // same convention as the SQL editor. Every act re-renders the panel: on
  // success it shows the recorded decision (the row leaves the queue on the
  // next master re-fetch); on failure, the note.
  review: (ctx) => {
    const id = ctx.params.get("id") || "";
    const action = ctx.params.get("action") || "";
    const reason = ((ctx.body && ctx.body.reason) || "").trim();
    const flags = { elevate: "--elevate", changes: "--changes", dismiss: "--dismiss" };
    if (!flags[action]) return renderDeltaDetail(id, `Acción inválida: ${action}`);
    if (!reason && action !== "elevate") return renderDeltaDetail(id, "Toda decisión lleva su porqué — escribe la razón.");
    const args = [id, flags[action]];
    if (reason) args.push("--reason", reason);
    const r = ctx.run(REVIEW_SCRIPT, args);
    const failed = r && r.ok === false;
    return renderDeltaDetail(id, failed ? r.error || "Falló la decisión (ver logs del viz)" : null);
  },
};

// Routed block: GET /c/delta-detail/frag/panel?id=<key> (empty id → empty
// state, the same handler the pattern seeds the panel with).
module.exports = {
  id: "delta-detail",
  manifest: { slot: "detail", frag: "panel", width: "34rem", selSignal: "selectedDelta", writes: [REVIEW_SCRIPT] },
  frags: { panel: (ctx) => renderDeltaDetail(ctx.params.get("id") || "") },
  acts,
  renderDeltaDetail,
};
