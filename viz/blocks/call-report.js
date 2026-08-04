// call-report block (#call-report) — view-only detail panel for ONE sales
// call: header (lead, closer, resultado, probabilidad, score) + the analysis
// report section by section — métricas, estructura de la llamada (5 fases),
// evaluación del closer + coaching, objeciones (con la respuesta del closer y
// la sugerencia de la IA), momentos críticos, perfil del lead y marketing
// insights. The HTML twin of bash/calls/call_show.sh, over the `call_detail`
// source. Long prose collapses into <details> so the panel stays scannable.

const { fetchSource } = require("../lib/datasources");
const { escape, section } = require("../lib/kit");

function panelShell(inner) {
  return `<div id="call-report" class="w-[36rem] h-full overflow-y-auto">${inner}</div>`;
}

function callReportEmpty() {
  return panelShell(
    `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
      <p>Selecciona una llamada para ver su análisis.</p>
    </div>`
  );
}

const RESULT_BADGE = [
  [/^closed won/i, "bg-emerald-100 text-emerald-700"],
  [/^follow-up/i, "bg-blue-100 text-blue-700"],
  [/^rescheduled/i, "bg-amber-100 text-amber-700"],
  [/unsuccessful|unqualified/i, "bg-red-100 text-red-700"],
];

function prose(text) {
  return `<p class="text-sm text-slate-700 whitespace-pre-wrap leading-relaxed">${escape(text)}</p>`;
}

// A collapsed block: summary line + prose body (keeps long analyses tidy).
function fold(label, text, open = false) {
  if (!text) return "";
  return `<details${open ? " open" : ""} class="mb-1.5">
    <summary class="cursor-pointer select-none text-sm text-slate-700 hover:text-indigo-700">${escape(label)}</summary>
    <div class="mt-1 pl-3 border-l-2 border-slate-100">${prose(text)}</div>
  </details>`;
}

function listItems(items) {
  const arr = Array.isArray(items) ? items : items ? [items] : [];
  if (!arr.length) return "";
  return `<ul class="list-disc list-inside text-sm text-slate-700 space-y-0.5">${arr.map((x) => `<li>${escape(x)}</li>`).join("")}</ul>`;
}

function metricsBlock(gm) {
  if (!gm || !gm.length) return "";
  const rows = gm
    .map(
      (x) => `<div class="flex gap-2 text-sm"><dt class="text-slate-400 w-56 shrink-0">${escape(x.metric || "—")}</dt>
      <dd class="text-slate-700 font-medium">${escape(x.result ?? "—")}</dd></div>`
    )
    .join("");
  return section("Métricas", null, `<dl class="space-y-1">${rows}</dl>`);
}

function structureBlock(cs) {
  if (!cs || !Object.keys(cs).length) return "";
  const FASES = [
    ["initialRapport", "Rapport"],
    ["frameSetting", "Frame"],
    ["qualification", "Calificación"],
    ["programPresentation", "Presentación"],
    ["closing", "Cierre"],
  ];
  const inner = FASES.map(([k, l]) => fold(l, cs[k])).join("");
  return inner ? section("Estructura de la llamada", null, inner) : "";
}

function evaluationBlock(fe) {
  if (!fe || !Object.keys(fe).length) return "";
  const score = fe.overallScore;
  const strengths = (fe.strengths || {}).items || [];
  const improve = (fe.areasForImprovement || {}).items || [];
  const coach = fe.coachingRecommendation || [];
  const inner = `
    ${strengths.length ? `<p class="text-[11px] font-semibold text-emerald-600 mb-1">Fortalezas</p>${listItems(strengths)}` : ""}
    ${improve.length ? `<p class="text-[11px] font-semibold text-amber-600 mt-2 mb-1">Áreas de mejora</p>${listItems(improve)}` : ""}
    ${coach.length ? `<p class="text-[11px] font-semibold text-indigo-600 mt-2 mb-1">Coaching</p>${listItems(coach)}` : ""}`;
  return section(`Evaluación del closer${score != null && score !== "" ? ` · ${score}/10` : ""}`, null, inner);
}

function objectionsBlock(oh) {
  const objs = (oh || {}).objections || [];
  if (!(oh || {}).summary && !objs.length) return "";
  const items = objs
    .map((o) => {
      const overcome = /overcome/i.test(o.status || "") && !/not/i.test(o.status || "");
      return `<li class="rounded-lg border ${overcome ? "border-emerald-100 bg-emerald-50/50" : "border-red-100 bg-red-50/50"} px-3 py-2">
      <p class="text-sm text-slate-800">${escape(o.objection || "—")}</p>
      <p class="text-[11px] ${overcome ? "text-emerald-600" : "text-red-600"} mt-0.5">${escape(o.status || "")}</p>
      ${fold("respuesta del closer", o.closerResponse)}
      ${fold("sugerencia de la IA", o.aiSuggestion)}
    </li>`;
    })
    .join("");
  const inner = `${oh.summary ? `<p class="text-xs text-slate-500 mb-2">${escape(oh.summary)}</p>` : ""}<ul class="space-y-2">${items}</ul>`;
  return section("Objeciones", objs.length || null, inner);
}

function momentsBlock(cm) {
  if (!cm || !cm.length) return "";
  const SEV = { High: "text-red-600", Medium: "text-amber-600", Low: "text-slate-500" };
  const inner = `<ul class="space-y-1">${cm
    .map(
      (x) => `<li class="text-sm text-slate-700"><span class="font-mono text-xs text-slate-400">${escape(x.timestamp || "—")}</span>
      <span class="text-[11px] font-semibold ${SEV[x.severity] || "text-slate-500"}">[${escape(x.severity || "?")}]</span>
      ${escape(x.momentName || "")}</li>`
    )
    .join("")}</ul>`;
  return section("Momentos críticos", cm.length, inner);
}

function leadBlock(lp) {
  if (!lp || !Object.keys(lp).length) return "";
  const bant = lp.bantAnalysis || {};
  const seg = lp.intelligentSegmentation || {};
  const pred = lp.predictionsAndRecommendations || {};
  const bantLine = Object.entries(bant)
    .filter(([, v]) => v && typeof v === "object")
    .map(([k, v]) => `${k.charAt(0).toUpperCase() + k.slice(1)} <b>${escape(v.score ?? "?")}</b>`)
    .join(" · ");
  const arch = (seg.archetype || {}).name;
  const prio = (seg.priorityClassification || {}).priority;
  const strat = pred.recommendedClosingStrategy || [];
  const inner = `
    ${bantLine ? `<p class="text-sm text-slate-700 mb-1">BANT: ${bantLine}</p>` : ""}
    ${arch ? `<p class="text-sm text-slate-700">Arquetipo: <b>${escape(arch)}</b>${prio ? ` · prioridad ${escape(prio)}` : ""}</p>` : ""}
    ${pred.recommendedOfferType ? `<p class="text-sm text-slate-700 mt-1">Oferta sugerida: ${escape(pred.recommendedOfferType)}</p>` : ""}
    ${strat.length ? `<p class="text-[11px] font-semibold text-slate-500 mt-2 mb-1">Estrategia recomendada</p>${listItems(strat)}` : ""}`;
  return inner.trim() ? section("Perfil del lead", null, inner) : "";
}

function marketingBlock(mi) {
  if (!mi || !Object.keys(mi).length) return "";
  const inner = `${fold("Calidad del lead", mi.leadQuality, true)}${fold("Recomendación", mi.recommendations)}${fold("Acción sugerida", mi.suggestedAction)}`;
  return section("Marketing (feedback a narrativas)", null, inner);
}

function renderCallReport(id) {
  if (!id) return callReportEmpty();
  let d, err;
  try {
    d = fetchSource("call_detail", { id }).rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err || !d) {
    return panelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(err || "Llamada no encontrada")}</div></div>`
    );
  }
  const rep = d.report || {};
  const badgeCls = (RESULT_BADGE.find(([re]) => re.test(d.result || "")) || [null, "bg-slate-100 text-slate-600"])[1];
  const header = `<div class="flex items-start gap-2 mb-1">
      <button data-on:click="$detailOpen=false; $selectedCall=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>
    </div>
    <h2 class="text-base font-semibold text-slate-800 mb-2 -mt-6 pr-6">${escape(d.lead || d.name || "Llamada")}</h2>
    <div class="flex flex-wrap items-center gap-2 mb-3">
      ${d.result ? `<span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${badgeCls}">${escape(d.result)}</span>` : ""}
      ${d.prob != null && d.prob !== "" ? `<span class="text-xs text-slate-600">prob. <b>${escape(d.prob)}%</b></span>` : ""}
      ${d.score != null && d.score !== "" ? `<span class="text-xs text-slate-600">score <b>${escape(d.score)}/10</b></span>` : ""}
    </div>
    <dl class="text-sm space-y-1 mb-5">
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Fecha</dt><dd class="text-slate-700">${escape(d.start || "—")}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Programa</dt><dd class="text-slate-700">${escape(d.program || "—")}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Proyecto</dt><dd class="text-slate-700">${escape(d.project || "—")}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Closer</dt><dd class="text-slate-700">${escape(d.closer || "— (sin resolver)")}</dd></div>
      ${d.payment_date ? `<div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Pago</dt><dd class="text-slate-700">${escape(d.payment_date)}</dd></div>` : ""}
    </dl>`;

  const body = !Object.keys(rep).length
    ? '<div class="rounded-lg border border-slate-200 bg-slate-50 text-slate-500 p-4 text-sm">Esta llamada aún no tiene reporte de análisis.</div>'
    : `${metricsBlock(rep.generalMetrics)}
       ${structureBlock((rep.performanceInsights || {}).callStructure)}
       ${evaluationBlock((rep.performanceInsights || {}).finalCloserEvaluation)}
       ${objectionsBlock((rep.objectionsAndInsights || {}).objectionHandling)}
       ${momentsBlock(((rep.performanceInsights || {}).sentimentAndEmotionAnalysis || {}).criticalMomentsDetected)}
       ${leadBlock(rep.leadProfile)}
       ${marketingBlock((rep.performanceInsights || {}).marketingInsights)}
       ${rep.aiAgentConclusion ? section("Conclusión del agente", null, prose(rep.aiAgentConclusion)) : ""}`;

  return panelShell(`<div class="p-5">${header}${body}</div>`);
}

module.exports = {
  id: "call-report",
  manifest: { slot: "detail", frag: "panel", width: "36rem", selSignal: "selectedCall" },
  frags: { panel: (ctx) => renderCallReport(ctx.params.get("id") || "") },
  renderCallReport,
};
