// org-detail block (#org-detail) — the DETAIL slot of the Flota: the ficha of
// ONE org from the `fleet_org_detail` source (docs/torre-de-control.md, T4).
// View-only (no acts): identity, mirror state, copilots with their pending
// deltas, the org's recent telemetry events and governance decisions. Only
// structure — the panel never shows client data, by construction of the
// source (git metadata + registry files).

const { fetchSource } = require("../lib/datasources");
const { escape, section } = require("../lib/kit");

function panelShell(inner) {
  return `<div id="org-detail" class="w-[32rem] h-full overflow-y-auto">${inner}</div>`;
}

function orgDetailEmpty() {
  return panelShell(
    `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
      <p>Selecciona una org para ver su ficha.</p>
    </div>`
  );
}

function metaRow(label, value) {
  if (!value) return "";
  return `<div class="flex gap-2 text-xs"><span class="w-20 shrink-0 text-slate-400">${escape(label)}</span><span class="text-slate-700 break-all">${escape(value)}</span></div>`;
}

function copilotsBlock(items) {
  if (!items || !items.length) return section("Copilotos", 0, '<p class="text-xs text-slate-400 italic">Sin forks de copiloto.</p>');
  const inner = `<ul class="space-y-2">${items
    .map(
      (c) => `<li class="rounded-lg border border-slate-200 px-3 py-2">
        <p class="text-sm font-medium text-slate-800">${escape(c.employee)} <span class="text-xs font-normal text-slate-400">· ${escape(c.role || "?")}</span></p>
        <p class="text-xs text-slate-500 mt-0.5 font-mono">${escape(c.fork)} @ ${escape(c.head)} · +${c.commits_ahead} commit(s)</p>
        <p class="text-xs text-slate-400 mt-0.5">última actividad ${escape((c.ultima_actividad || "").slice(0, 10))}${c.deltas_pend ? ` · <span class="text-indigo-600 font-medium">${c.deltas_pend} delta(s) en cola</span>` : ""}</p>
      </li>`
    )
    .join("")}</ul>`;
  return section("Copilotos", items.length, inner);
}

function eventsBlock(items) {
  if (!items || !items.length) return "";
  const inner = `<ul class="space-y-1.5">${items
    .map((e) => {
      const classes = Object.entries(e.classes || {})
        .map(([c, n]) => `${c}×${n}`)
        .join(" · ");
      return `<li class="text-xs text-slate-600">
        <span class="text-slate-400 font-mono">${escape((e.ts || "").slice(0, 16).replace("T", " "))}</span>
        ${escape(e.ref === "refs/heads/main" ? "main" : e.ref || "")} · ${e.commits || 0} commit(s)
        ${classes ? `<span class="text-slate-400">· ${escape(classes)}</span>` : ""}
      </li>`;
    })
    .join("")}</ul>`;
  return section("Últimos pushes", items.length, inner);
}

function decisionsBlock(items) {
  if (!items || !items.length) return "";
  const ES = { elevated: "Elevada", changes_requested: "Cambios pedidos", dismissed: "Descartada" };
  const inner = `<ul class="space-y-1.5">${items
    .map(
      (d) => `<li class="text-xs text-slate-600">
        <span class="text-slate-400 font-mono">${escape((d.ts || "").slice(0, 10))}</span>
        <span class="font-medium">${escape(ES[d.action] || d.action)}</span> ${escape(d.delta)}
      </li>`
    )
    .join("")}</ul>`;
  return section("Decisiones recientes", items.length, inner);
}

function renderOrgDetail(id) {
  if (!id) return orgDetailEmpty();
  let d, err;
  try {
    const { rows } = fetchSource("fleet_org_detail", { id });
    d = rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err || !d) {
    return panelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(err || "Org no encontrada")}</div></div>`
    );
  }
  const closeBtn = `<button data-on:click="$detailOpen=false; $selectedOrg=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>`;
  const mir = d.espejo_estado;
  const header = `<div class="flex items-start gap-2 mb-1">${closeBtn}</div>
    <h2 class="text-base font-semibold text-slate-800 mb-1 -mt-6 pr-6">${escape(d.nombre || d.org)}</h2>
    <p class="text-xs text-slate-500 mb-3">${escape(d.org)} · vertical ${escape(d.vertical || "?")}</p>`;

  const identity = `<div class="space-y-1 mb-3">
    ${metaRow("repo", d.repo)}
    ${metaRow("head", d.head)}
    ${metaRow("pulso", d.pulso)}
    ${metaRow("módulos", (d.modules || []).join(", "))}
    ${d.nota ? metaRow("nota", d.nota) : ""}
  </div>`;

  const espejo = mir
    ? section(
        "Espejo",
        null,
        `<div class="rounded-lg border ${mir.ok ? "border-emerald-200 bg-emerald-50" : "border-red-200 bg-red-50"} px-3 py-2 text-xs">
          <p class="${mir.ok ? "text-emerald-700" : "text-red-700"} font-medium">${mir.ok ? "✓ OK" : "✗ FALLÓ"} <span class="font-normal text-slate-500">· ${escape(mir.ts)}</span></p>
          <p class="text-slate-500 font-mono mt-0.5 break-all">${escape(mir.url)}</p>
        </div>`
      )
    : "";

  return panelShell(
    `<div class="p-5">${header}${identity}${espejo}${copilotsBlock(d.copilotos)}${eventsBlock(d.eventos)}${decisionsBlock(d.decisiones)}</div>`
  );
}

// Routed block: GET /c/org-detail/frag/panel?id=<org>.
module.exports = {
  id: "org-detail",
  manifest: { slot: "detail", frag: "panel", width: "32rem", selSignal: "selectedOrg" },
  frags: { panel: (ctx) => renderOrgDetail(ctx.params.get("id") || "") },
  renderOrgDetail,
};
