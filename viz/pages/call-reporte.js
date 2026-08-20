// call-reporte page — EL REPORTE de una llamada como página standalone,
// direccionable por ?meeting=<id|prefijo>. Es la cara pública del reporte del
// Cerebro (call_report_vigente vía call_show.sh): la lista de llamadas le
// apunta, y el escenario 6 de WhatsApp puede mandar este link en vez de texto.
//
// Guard de identidad: si el despliegue fuerza closer_id (plantilla $user_id),
// la llamada debe pertenecer a ese closer — se verifica contra la fuente
// closer_llamadas (fila vacía = mismo render que un meeting inexistente, no
// se filtra qué existe). El DC (identidad {}) abre cualquiera.
//
// La descarga del transcript usa el relay del publicador (params.base_t,
// fijado al publicar); sin relay (viz local) se declara en vez de esconderse.
const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };

const kpi = (label, value, tone = "brand", sub = "") => `<div class="card card-pad kpi">
  <span class="kpi-label">${escape(label)}</span>
  <span class="kpi-value tabular-nums" style="color:${TONE[tone]}">${value}</span>
  ${sub ? `<span class="kpi-foot">${escape(sub)}</span>` : ""}
</div>`;

const section = (t) => `<h2 class="text-sm font-bold uppercase tracking-wider mt-10 mb-3" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(t)}</h2>`;

const lista = (items, ink) =>
  (Array.isArray(items) ? items : items ? [items] : [])
    .map((x) => `<li class="mb-1 text-sm" style="color:${ink || "var(--text-2)"}">${escape(String(x))}</li>`)
    .join("");

const noExiste = (pane) => `<section id="pane" class="${pane}">
  <div class="max-w-3xl mx-auto p-10 text-center">
    <p class="text-lg font-semibold" style="color:var(--text-1)">Esa llamada no existe.</p>
    <p class="text-sm mt-2" style="color:var(--text-3)">Verifica el link — o vuelve a tu lista de llamadas.</p>
  </div></section>`;

function renderCallReporte(ui) {
  const p = ui.params || {};
  const PANE = "flex-1 overflow-auto p-6";
  const meeting = String(p.meeting || "").replace(/[^0-9a-fA-F-]/g, "");
  if (!meeting) return noExiste(PANE);

  // Guard de identidad ANTES de tocar el detalle.
  if (p.closer_id) {
    try {
      const g = fetchSource("closer_llamadas", { closer_id: p.closer_id, meeting, limit: "1" }).rows || [];
      if (!g.length) return noExiste(PANE);
    } catch (e) {
      return noExiste(PANE);
    }
  }

  let d;
  try {
    d = fetchSource("call_detail", { id: meeting }).rows[0];
  } catch (e) {
    d = null;
  }
  if (!d || !d.id) return noExiste(PANE);

  const r = d.report || {};
  const gi = r.generalInformation || {};
  const evalua = (r.performanceInsights || {}).finalCloserEvaluation || {};
  const lp = r.leadProfile || {};
  const bant = lp.bantAnalysis || {};
  const seg = lp.intelligentSegmentation || {};
  const pred = lp.predictionsAndRecommendations || {};
  const objs = ((r.objectionsAndInsights || {}).objectionHandling || {}).objections || [];
  const gen = r._generacion || {};

  const bantScore = (k) => {
    const v = Number(((bant[k] || {}).score ?? "").toString().replace(/[^0-9.]/g, ""));
    return Number.isNaN(v) ? null : Math.round(v);
  };
  const bantItems = ["need", "budget", "authority", "timeline"].map((k) => ({ k, v: bantScore(k) }));
  const conBant = bantItems.some((b) => b.v != null && b.v > 0);

  const header = `<div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">${escape(d.lead || gi.leadName || "—")}</h1>
      <span class="text-sm" style="color:var(--text-3)">${escape(d.program || "—")} · ${escape(d.project || "—")}</span>
      <span class="badge badge-neutral">${escape(d.start || "")}</span>
      <span class="badge badge-brand">${escape(d.closer || "—")}</span>
      ${gi.callStatus ? `<span class="badge badge-neutral">${escape(String(gi.callStatus).slice(0, 40))}</span>` : ""}
      ${gen.prompt_variante ? `<span class="badge badge-pos" title="Reporte del Cerebro (${escape(gen.prompt_variante || "")}, ${escape(String(gen.n_tiradas || ""))} tiradas, mediana)">cerebro</span>` : ""}
    </div>`;

  const descarga = d.has_transcript
    ? p.base_t
      ? `<a href="${escape(String(p.base_t))}/${escape(d.id)}" class="btn btn-sm inline-flex items-center gap-2">⬇ Descargar transcript (.txt)</a>`
      : `<span class="text-xs" style="color:var(--text-3)">Transcript disponible — descarga en la versión publicada.</span>`
    : `<span class="text-xs" style="color:var(--text-3)">Esta llamada no dejó transcript.</span>`;

  if (!d.report) {
    return `<section id="pane" class="${PANE}"><div class="max-w-4xl mx-auto">
      ${header}
      <p class="mt-6 text-sm" style="color:var(--text-2)">Esta llamada aún no tiene reporte de análisis.</p>
      <div class="mt-4">${descarga}</div>
    </div></section>`;
  }

  const kpis = `<div class="grid gap-3 mt-6" style="grid-template-columns:repeat(auto-fit,minmax(10rem,1fr))">
    ${kpi("Desempeño del closer", d.score != null ? `${escape(String(d.score))}<span class="text-sm" style="color:var(--text-3)">/10</span>` : "—", d.score >= 7 ? "pos" : d.score >= 5 ? "cau" : "neg")}
    ${kpi("Prob. de cierre", d.prob != null ? `${escape(String(d.prob))}%` : "—")}
    ${conBant ? bantItems.map((b) => kpi(b.k.toUpperCase(), b.v != null ? String(b.v) : "—", b.v >= 81 ? "pos" : b.v >= 61 ? "cau" : "muted", (gen.baja_confianza || []).includes(b.k) ? "baja confianza" : "")).join("") : ""}
  </div>`;

  const evalBloque = `
    ${section("Evaluación del closer")}
    <div class="card card-pad grid gap-4" style="grid-template-columns:repeat(auto-fit,minmax(14rem,1fr))">
      <div><p class="text-[11px] font-semibold uppercase mb-1" style="color:${TONE.pos}">Fortalezas</p><ul class="list-disc ml-4">${lista((evalua.strengths || {}).items || evalua.strengths)}</ul></div>
      <div><p class="text-[11px] font-semibold uppercase mb-1" style="color:${TONE.cau}">Áreas de mejora</p><ul class="list-disc ml-4">${lista((evalua.areasForImprovement || {}).items || evalua.areasForImprovement)}</ul></div>
      <div><p class="text-[11px] font-semibold uppercase mb-1" style="color:${TONE.brand}">Coaching</p><ul class="list-disc ml-4">${lista(evalua.coachingRecommendation)}</ul></div>
    </div>`;

  const objBloque = objs.length
    ? `${section("Objeciones")}
      <div class="table-wrap"><div class="table-scroll"><table class="tbl">
        <thead><tr><th>Estado</th><th>Objeción</th><th>Respuesta del closer</th><th>Sugerencia IA</th></tr></thead>
        <tbody>${objs
          .map(
            (o) => `<tr>
          <td class="align-top"><span class="badge ${/overcome|superad/i.test(o.status || "") && !/not/i.test(o.status || "") ? "badge-pos" : "badge-neutral"}">${escape(o.status || "—")}</span></td>
          <td class="align-top"><span class="text-xs">${escape(String(o.objection || "").slice(0, 200))}</span></td>
          <td class="align-top"><span class="text-xs" style="color:var(--text-2)">${escape(String(o.closerResponse || "").slice(0, 200))}</span></td>
          <td class="align-top"><span class="text-xs" style="color:var(--text-3)">${escape(String(o.aiSuggestion || "").slice(0, 200))}</span></td>
        </tr>`
          )
          .join("")}</tbody></table></div></div>`
    : "";

  // archetype llega como {name, description} (canon), a veces como string
  // plano; recommendedClosingStrategy es un ARRAY de pasos.
  const arqObj = seg.archetype || seg.arquetipo || "";
  const arquetipo = typeof arqObj === "string" ? arqObj : arqObj.name || "";
  const arqDesc = typeof arqObj === "object" && arqObj ? String(arqObj.description || "") : "";
  const estrategiaRaw =
    pred.recommendedClosingStrategy || pred.recommendedStrategy || pred.closingStrategy || pred.strategy || "";
  const estrategiaPasos = (Array.isArray(estrategiaRaw) ? estrategiaRaw : estrategiaRaw ? [estrategiaRaw] : [])
    .map((s) => String(typeof s === "string" ? s : s.description || s.step || JSON.stringify(s)).slice(0, 400));
  const perfilBloque =
    arquetipo || estrategiaPasos.length
      ? `${section("Perfil del lead")}
       <div class="card card-pad">
         ${arquetipo ? `<p class="text-sm"><span class="font-semibold" style="color:var(--text-1)">Arquetipo:</span> <span class="badge badge-brand">${escape(arquetipo)}</span></p>` : ""}
         ${arqDesc ? `<p class="text-sm mt-1" style="color:var(--text-2)">${escape(arqDesc.slice(0, 600))}</p>` : ""}
         ${estrategiaPasos.length ? `<p class="text-sm mt-3 font-semibold" style="color:var(--text-1)">Estrategia sugerida:</p><ul class="list-disc ml-4 mt-1">${estrategiaPasos.map((s) => `<li class="mb-1 text-sm" style="color:var(--text-2)">${escape(s)}</li>`).join("")}</ul>` : ""}
       </div>`
      : "";

  const conclusion = r.aiAgentConclusion
    ? `${section("Conclusión")}
       <div class="card card-pad"><p class="text-sm" style="color:var(--text-2)">${escape(String(typeof r.aiAgentConclusion === "string" ? r.aiAgentConclusion : r.aiAgentConclusion.conclusion || JSON.stringify(r.aiAgentConclusion)).slice(0, 2000))}</p></div>`
    : "";

  return `<section id="pane" class="${PANE}"><div class="max-w-4xl mx-auto">
    ${header}
    ${kpis}
    ${evalBloque}
    ${objBloque}
    ${perfilBloque}
    ${conclusion}
    <div class="mt-10">${descarga}</div>
  </div></section>`;
}

module.exports = {
  id: "call-reporte",
  manifest: { consumes: "object", overridable: ["meeting"] },
  render: renderCallReporte,
};
