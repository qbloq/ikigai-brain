// meeting-detail block (#meeting-detail) — view-only render of one team
// meeting's structured report (the Spanish jsonb from meeting_show.sh --json).
// SSE-patched by the /meeting/:id route.

const { fetchSource } = require("../lib/datasources");
const { escape, section, PRIORITY_DOT } = require("../lib/kit");

function meetingPanelShell(inner) {
  return `<div id="meeting-detail" class="w-[32rem] h-full overflow-y-auto">${inner}</div>`;
}

function meetingDetailEmpty() {
  return meetingPanelShell(
    `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
      <p>Selecciona una reunión para ver su reporte.</p>
    </div>`
  );
}

function prose(text) {
  return `<p class="text-sm text-slate-700 whitespace-pre-wrap leading-relaxed">${escape(text)}</p>`;
}

function objectivesBlock(o) {
  if (!o || typeof o !== "object") return "";
  const row = (label, v) =>
    v
      ? `<div class="mb-2"><p class="text-[11px] font-semibold text-slate-400">${escape(label)}</p>${prose(v)}</div>`
      : "";
  const inner = row("Planteado", o.stated) + row("Logrado", o.achieved) + row("Sin resolver", o.unresolved);
  return inner ? section("Objetivos", null, inner) : "";
}

function decisionsBlock(items) {
  if (!items || !items.length) return "";
  const inner = `<ul class="space-y-3">${items
    .map(
      (d) => `<li class="border-l-2 border-indigo-100 pl-3">
        <p class="text-sm font-medium text-slate-800">${escape(d.topic || "—")}</p>
        ${d.summary ? `<p class="text-xs text-slate-500 mt-0.5">${escape(d.summary)}</p>` : ""}
        ${d.decision ? `<p class="text-sm text-slate-700 mt-1"><span class="text-[11px] font-semibold uppercase text-emerald-600">Decisión:</span> ${escape(d.decision)}</p>` : ""}
        ${d.rationale ? `<p class="text-xs text-slate-400 mt-0.5 italic">${escape(d.rationale)}</p>` : ""}
      </li>`
    )
    .join("")}</ul>`;
  return section("Decisiones", items.length, inner);
}

function actionItemsBlock(items) {
  if (!items || !items.length) return "";
  const inner = `<ul class="space-y-2.5">${items
    .map((a) => {
      const prio = PRIORITY_DOT[a.priority];
      const who = Array.isArray(a.assignedTo) ? a.assignedTo.join(", ") : a.assignedTo;
      return `<li class="flex items-start gap-2">
        ${prio ? `<span class="inline-block w-2.5 h-2.5 rounded-full ${prio.c} mt-1.5 shrink-0" title="${escape(prio.t)}"></span>` : '<span class="w-2.5 shrink-0"></span>'}
        <div class="min-w-0">
          <p class="text-sm text-slate-700">${escape(a.task)}</p>
          <p class="text-xs text-slate-400">${who ? escape(who) : "—"}${a.dueDate ? ` · ${escape(a.dueDate)}` : ""}${a.dependencies && a.dependencies !== "Ninguna" ? ` · dep: ${escape(a.dependencies)}` : ""}</p>
        </div>
      </li>`;
    })
    .join("")}</ul>`;
  return section("Action items", items.length, inner);
}

function blockersBlock(items) {
  if (!items || !items.length) return "";
  const inner = `<ul class="space-y-2.5">${items
    .map(
      (b) => `<li class="rounded-lg bg-red-50 border border-red-100 px-3 py-2">
        <p class="text-sm text-slate-800">${escape(b.issue || "—")}</p>
        ${b.status ? `<p class="text-xs text-red-600 mt-0.5">${escape(b.status)}</p>` : ""}
        ${b.nextSteps ? `<p class="text-xs text-slate-500 mt-0.5">→ ${escape(b.nextSteps)}</p>` : ""}
      </li>`
    )
    .join("")}</ul>`;
  return section("Bloqueos críticos", items.length, inner);
}

function nextStepsBlock(o) {
  if (!o || typeof o !== "object") return "";
  const list = (label, v) => {
    if (!v) return "";
    const arr = Array.isArray(v) ? v : [v];
    if (!arr.length) return "";
    return `<div class="mb-2"><p class="text-[11px] font-semibold text-slate-400">${escape(label)}</p>
      <ul class="list-disc list-inside text-sm text-slate-700 space-y-0.5">${arr.map((x) => `<li>${escape(x)}</li>`).join("")}</ul></div>`;
  };
  const inner = list("Próxima reunión", o.nextMeeting) + list("Puntos de revisión", o.reviewPoints) + list("Hitos clave", o.keyMilestones);
  return inner ? section("Próximos pasos", null, inner) : "";
}

function renderMeetingDetail(id) {
  if (!id) return meetingDetailEmpty();
  let rep, err;
  try {
    const { rows } = fetchSource("meeting_detail", { id });
    rep = rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return meetingPanelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(err)}</div></div>`
    );
  }
  const closeBtn = `<button data-on:click="$detailOpen=false; $selectedMeeting=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>`;
  if (!rep || !Object.keys(rep).length) {
    return meetingPanelShell(
      `<div class="p-5"><div class="flex items-start mb-3">${closeBtn}</div>
        <div class="rounded-lg border border-slate-200 bg-slate-50 text-slate-500 p-4 text-sm">Esta reunión aún no tiene reporte.</div></div>`
    );
  }
  const header = `<div class="flex items-start gap-2 mb-1">${closeBtn}</div>
    <h2 class="text-base font-semibold text-slate-800 mb-1 -mt-6 pr-6">${escape(rep.reportTitle || "Reporte")}</h2>
    ${rep.reportSubtitle ? `<p class="text-sm text-slate-500 mb-4">${escape(rep.reportSubtitle)}</p>` : '<div class="mb-4"></div>'}`;

  const inner = `<div class="p-5">
    ${header}
    ${rep.executiveSummary ? section("Resumen ejecutivo", null, prose(rep.executiveSummary)) : ""}
    ${objectivesBlock(rep.meetingObjectives)}
    ${decisionsBlock(rep.discussionPointsAndDecisions)}
    ${actionItemsBlock(rep.actionItems)}
    ${blockersBlock(rep.criticalIssuesAndBlockers)}
    ${nextStepsBlock(rep.nextStepsAndFollowUp)}
  </div>`;
  return meetingPanelShell(inner);
}

// Routed block (paso 3). Canonical: GET /c/meeting-detail/frag/panel?id=… —
// alias GET /meeting/:id (empty id → empty state).
module.exports = {
  id: "meeting-detail",
  frags: { panel: (ctx) => renderMeetingDetail(ctx.params.get("id") || "") },
  renderMeetingDetail,
};
