// survey-censo page — el CENSO del survey de calificación: cada pregunta del
// formulario de agendamiento con su cobertura real, la distribución de sus
// respuestas y la conversión A PLATA por respuesta.
//
// Es la generalización sistemática de docs/lead-score.md §3 (que eligió a mano
// las dos preguntas que discriminan) y el baseline del loop A/B de survey:
// antes de cambiar el instrumento hay que saber qué mide hoy. La salud de cada
// pregunta se lee en dos números, y la página los pinta como badges:
//
//   planitud — % de la respuesta modal. ≥85% = pregunta plana: casi todos
//              contestan lo mismo, no puede discriminar (el «need a 95» del
//              experimento BANT, versión formulario).
//   spread   — max−min de conversión entre respuestas con n≥20. ≥5pp = la
//              pregunta ordena leads de verdad.
//
// Consume `survey_censo` (object) — bash/crm/survey_censo.sh, read-only.
// La verdad es plata (payment_plan con cuota Paid posterior a la primera
// oportunidad del contacto), no `status='won'` ni `callStatus`.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };

// Umbrales de lectura (los mismos que declara el script y la nota al pie):
const VIVA_MIN = 30;   // respuestas para que una pregunta entre al análisis
const CELDA_MIN = 20;  // n por respuesta para que su conversión sea legible
const PLANA = 85;      // planitud ≥ → pregunta plana
const SPREAD_OK = 5;   // spread en pp ≥ → discrimina

function num(v) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  return Number.isNaN(n) ? escape(String(v)) : n.toLocaleString("es-CO");
}

function kpi(label, value, { tone = "brand", sub = "", title = "" } = {}) {
  return `<div class="card card-pad kpi"${title ? ` title="${escape(title)}"` : ""}>
    <span class="kpi-label">${escape(label)}</span>
    <span class="kpi-value tabular-nums" style="color:${TONE[tone] || TONE.brand}">${value}</span>
    ${sub ? `<span class="kpi-foot">${escape(sub)}</span>` : ""}
  </div>`;
}

function badge(txt, cls, title = "") {
  return `<span class="badge ${cls}"${title ? ` title="${escape(title)}"` : ""}>${escape(txt)}</span>`;
}

// La barra de conversión por respuesta. Gris cuando n < CELDA_MIN: con esas
// muestras la diferencia es ruido, y pintarla de color la volvería hallazgo.
function convCell(pct, n, base) {
  const p = Number(pct) || 0;
  const chico = n < CELDA_MIN;
  const tone = chico ? TONE.muted : p >= base ? TONE.pos : TONE.cau;
  const bar = chico ? "var(--surface-3)" : p >= base ? "var(--pos-solid)" : "var(--cau-solid)";
  const w = Math.max(1, Math.min(100, (p / 30) * 100));
  return `<td class="whitespace-nowrap"><div class="flex items-center gap-2"${chico ? ` title="n < ${CELDA_MIN}: ruido, no señal"` : ""}>
    <span class="tabular-nums font-semibold" style="min-width:3.2rem;color:${tone}">${p.toFixed(1)}%</span>
    <span style="display:block;height:6px;border-radius:3px;width:${w}%;min-width:2px;background:${bar};${chico ? "opacity:.45" : ""}"></span>
  </div></td>`;
}

// Texto libre: la distribución por valor no dice nada (cientos de valores de
// n=1). Se declara como tal y se mide solo cobertura y conversión de quien
// respondió — la señal posible aquí es de *presencia*, no de contenido.
function esTextoLibre(q) {
  return q.n_valores > 30 && q.planitud_pct < 10;
}

function tarjetaPregunta(q, meta) {
  const base = Number(meta.conv_global_pct) || 0;
  const plana = Number(q.planitud_pct) >= PLANA;
  const discrimina = q.spread_pp != null && Number(q.spread_pp) >= SPREAD_OK;
  const libre = esTextoLibre(q);

  const badges = [
    badge(q.data_type || "?", "badge-neutral", "Tipo de campo en GHL"),
    badge(`cobertura ${q.cobertura_pct}%`, "badge-neutral", `${num(q.respondidas)} contactos la respondieron`),
    libre
      ? badge(`texto libre · ${num(q.n_valores)} valores`, "bg-slate-100 text-slate-600", "Distribución por valor no legible")
      : badge(`planitud ${q.planitud_pct}%`, plana ? "bg-amber-50 text-amber-700" : "badge-neutral",
          plana ? "≥85% contesta lo mismo: la pregunta no puede discriminar" : "% de la respuesta modal"),
    !libre && q.spread_pp != null
      ? badge(`spread ${q.spread_pp} pp`, discrimina ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-600",
          `max−min de conversión entre respuestas con n≥${CELDA_MIN}`)
      : "",
  ].filter(Boolean).join(" ");

  let cuerpo = "";
  if (libre) {
    cuerpo = `<p class="text-xs mt-2" style="color:var(--text-3)">
      Texto libre — ${num(q.n_valores)} valores distintos en ${num(q.respondidas)} respuestas.
      Conversión de quien respondió: <b style="color:${TONE.brand}">${q.conv_resp_pct}%</b>
      (la señal posible aquí es de presencia, no de contenido; su contenido pide normalización aparte).</p>`;
  } else {
    const filas = (q.valores || []).map((v) => {
      const chico = v.n < CELDA_MIN;
      return `<tr${chico ? ` style="color:var(--text-3)"` : ""}>
        <td class="align-top">${escape(v.valor || "—")}</td>
        <td class="tabular-nums text-right">${num(v.n)}</td>
        <td class="tabular-nums text-right">${num(v.pagaron)}</td>
        ${convCell(v.conv_pct, v.n, base)}
      </tr>`;
    }).join("");
    cuerpo = `<div class="table-wrap mt-2"><div class="table-scroll"><table class="tbl">
      <thead><tr><th>Respuesta</th><th class="text-right">Leads</th><th class="text-right">Pagaron</th><th>Conversión</th></tr></thead>
      <tbody>${filas}</tbody></table></div></div>
      ${q.valores_omitidos > 0 ? `<p class="text-[11px] mt-1" style="color:var(--text-3)">…y ${num(q.valores_omitidos)} valores más de menor n, omitidos.</p>` : ""}`;
  }

  return `<div class="card card-pad mb-3">
    <div class="flex items-start justify-between gap-3 flex-wrap">
      <p class="text-sm font-semibold max-w-3xl" style="color:var(--text-1)">${escape(q.campo)}</p>
      <div class="flex gap-1 flex-wrap shrink-0">${badges}</div>
    </div>
    ${cuerpo}
  </div>`;
}

function seccion(title, hint) {
  return `<div class="flex items-baseline gap-3 mt-10 mb-3 flex-wrap">
    <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(title)}</h2>
    ${hint ? `<span class="text-xs" style="color:var(--text-3)">${escape(hint)}</span>` : ""}
  </div>`;
}

function renderSurveyCenso(ui) {
  // una fuente `emits: "object"` igual vuelve envuelta: fetchSource siempre
  // devuelve {rows}, con el objeto como su única fila (ver pages/ontology.js).
  const { rows } = fetchSource(ui.source || "survey_censo", ui.params || {});
  const d = rows[0] || {};
  const m = d.meta || {};
  const proyectos = d.proyectos || [];

  const cabecera = `
    ${kpi("Contactos en el espejo", num(m.contactos), { sub: "universo del censo" })}
    ${kpi("Con survey respondido", num(m.con_encuesta), { sub: `${m.contactos ? Math.round((100 * m.con_encuesta) / m.contactos) : 0}% del universo` })}
    ${kpi("Conversión base", (m.conv_global_pct ?? 0) + "%", { tone: "pos", sub: "pagó tras su oportunidad", title: "Payment plan con cuota Paid, creado en o después de la primera oportunidad" })}
    ${kpi("Preguntas vivas", `${num(m.preguntas_vivas)} / ${num(m.preguntas_total)}`, { tone: m.preguntas_vivas < m.preguntas_total / 2 ? "cau" : "brand", sub: `≥${VIVA_MIN} respuestas · resto muerto en el catálogo` })}`;

  const secciones = proyectos.map((p) => {
    const vivas = (p.preguntas || []).filter((q) => !q.es_meta && q.respondidas >= VIVA_MIN);
    const goteo = (p.preguntas || []).filter((q) => !q.es_meta && q.respondidas < VIVA_MIN);
    const muertas = p.muertas || [];
    if (!vivas.length && !goteo.length && !muertas.length) return "";

    const tMenores = goteo.length
      ? `<details class="mt-3"><summary class="text-xs cursor-pointer" style="color:var(--text-3)">
           ${goteo.length} preguntas con menos de ${VIVA_MIN} respuestas (formularios viejos o recién lanzados) — ver</summary>
         <div class="table-wrap mt-2"><div class="table-scroll"><table class="tbl">
           <thead><tr><th>Pregunta</th><th>Tipo</th><th class="text-right">Respondidas</th></tr></thead>
           <tbody>${goteo.map((q) => `<tr><td>${escape(q.campo)}</td><td>${escape(q.data_type || "?")}</td>
             <td class="tabular-nums text-right">${num(q.respondidas)}</td></tr>`).join("")}</tbody>
         </table></div></div></details>` : "";

    const tMuertas = muertas.length
      ? `<details class="mt-2"><summary class="text-xs cursor-pointer" style="color:var(--text-3)">
           ${muertas.length} preguntas del catálogo que NADIE respondió — ver</summary>
         <div class="table-wrap mt-2"><div class="table-scroll"><table class="tbl">
           <thead><tr><th>Pregunta</th><th>Tipo</th></tr></thead>
           <tbody>${muertas.map((q) => `<tr style="color:var(--text-3)"><td>${escape(q.campo)}</td>
             <td>${escape(q.data_type || "?")}</td></tr>`).join("")}</tbody>
         </table></div></div></details>` : "";

    return `${seccion(p.proyecto, `${num(p.contactos)} contactos en el espejo`)}
      ${vivas.length ? vivas.map((q) => tarjetaPregunta(q, m)).join("") : `<p class="text-sm italic" style="color:var(--text-3)">Sin preguntas con cobertura ≥ ${VIVA_MIN} respuestas en el espejo.</p>`}
      ${tMenores}${tMuertas}`;
  }).join("");

  // `id="pane"` NO es decorativo: el servidor parchea por SSE sobre ese id —
  // sin él la navegación se queda pegada (ver lead-score.js).
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
    <div class="max-w-6xl">
    <header class="mb-4">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">Censo del survey de calificación</h1>
      <p class="text-xs mt-1" style="color:var(--text-3)">corte ${escape(d.corte || "—")} · verdad = plata (cuota pagada), no estado del CRM</p>
    </header>
    <p class="mb-4 text-xs max-w-4xl" style="color:var(--text-3)">
      El survey de agendamiento es el único score que existe <b>antes</b> de asignar la llamada
      (docs/lead-score.md). Este censo mide el instrumento completo: qué pregunta cada formulario,
      cuánta cobertura real tiene, y si sus respuestas <b>ordenan la plata</b>. Una pregunta con
      <b>planitud ≥ ${PLANA}%</b> está muerta aunque se responda mucho (todos contestan lo mismo);
      una con <b>spread ≥ ${SPREAD_OK} pp</b> discrimina y es candidata a entrar al score pre-llamada.
      ⚠️ Cada pregunta se mide solo sobre quienes la respondieron — «sin responder» no es una categoría
      comparable entre preguntas (poblaciones y épocas distintas). Filas en gris: n &lt; ${CELDA_MIN}, ruido.
    </p>
    <div class="grid gap-3 mb-2" style="grid-template-columns:repeat(auto-fit,minmax(13rem,1fr))">
      ${cabecera}
    </div>
    ${secciones}
    <p class="mt-8 text-[11px] max-w-4xl" style="color:var(--text-3)">
      Fuente: <code>bash/crm/survey_censo.sh</code> (read-only). Conversión: payment_plan con ≥1 cuota
      <code>Paid</code> creado en o después de la primera oportunidad del contacto — la misma verdad de
      <code>conversion_real.sh</code>, anclada a la oportunidad porque el universo son leads, no llamadas.
      El espejo CRM cubre un pipeline por proyecto (completo desde mayo 2026); Andrea casi no tiene
      survey en el espejo. Los campos <code>utm_*</code> quedan fuera (atribución, no survey).
    </p>
    </div>
  </section>`;
}

module.exports = {
  id: "survey-censo",
  manifest: { consumes: "object", overridable: [] },
  render: renderSurveyCenso,
};
