// plan-reactivacion page — el plan de reactivación de una cohorte en mora,
// leíble: la versión UI del Doc de la tarea 9f249dbe (arquetipo A12.4). El Doc
// queda como documento; esta página es para quien no lo va a leer entero.
//
// Los NÚMEROS salen vivos de `cohorte_mora` (una fila por estudiante en mora
// con su segmento por reglas declaradas) y de la misma fuente con `contexto`
// (una fila por cohorte mensual). KPIs, la curva «dónde se frena», los
// conteos y listas por segmento y la cobertura de contacto se calculan aquí
// sobre esas filas — nada se digita. El PLAN (acción, responsable, fecha por
// segmento; métricas; causa raíz; lo que falta) es copy curado en
// `params.texto` del spec: se cambia re-publicando, no en código.
//
// Reglas heredadas de la fuente: cohorte = fecha de inicio del plan; mora
// desde due_date (nunca desde el status); segmentos S1 ≤30 d · S2 ≤90 d ·
// S3 pagó ≥50 % · S4 el resto. La aprobación de Lorenzo es una atestación
// humana y la página lo dice: mientras no exista, esto es un borrador.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");
const { chartEl } = require("../blocks/charts");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };
const SEG_ORDER = ["S1", "S2", "S3", "S4"];
const SEG_BADGE = { S1: "badge-pos", S2: "badge-brand", S3: "badge-cau", S4: "badge-neg" };

const n0 = (v) => (v == null || v === "" || Number.isNaN(Number(v)) ? 0 : Number(v));
const num = (v, d = 0) => (v == null || v === "" ? "—" : n0(v).toLocaleString("es-CO", { maximumFractionDigits: d, minimumFractionDigits: d }));
const usd = (v) => (v == null || v === "" ? "—" : "$" + Math.round(n0(v)).toLocaleString("es-CO"));
const md = (t) => escape(String(t || "")).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>");

function kpi(label, value, { tone = "brand", sub = "", title = "" } = {}) {
  return `<div class="card card-pad kpi"${title ? ` title="${escape(title)}"` : ""}>
    <span class="kpi-label">${escape(label)}</span>
    <span class="kpi-value tabular-nums" style="color:${TONE[tone] || TONE.brand}">${value}</span>
    ${sub ? `<span class="kpi-foot">${sub}</span>` : ""}
  </div>`;
}
function section(title, hint) {
  return `<div class="flex items-baseline gap-3 mt-10 mb-3 flex-wrap">
    <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(title)}</h2>
    ${hint ? `<span class="text-xs" style="color:var(--text-3)">${escape(hint)}</span>` : ""}
  </div>`;
}
function tbl(headers, rows, { empty = "Sin datos." } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows.map((cells) => `<tr>${cells.map((c) => `<td class="align-top">${c}</td>`).join("")}</tr>`).join("");
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`;
}
const chartCard = (spec, sig, table) => `
  <div class="card card-pad" data-signals="{${sig}:false}">
    ${spec ? chartEl(spec) : `<p class="text-sm italic" style="color:var(--text-3)">Sin datos para graficar.</p>`}
    <div class="mt-3 pt-2" style="border-top:1px solid var(--border-1)">
      <button data-on:click="$${sig}=!$${sig}" class="text-xs" style="color:var(--text-brand)">
        <span data-text="$${sig} ? 'ocultar tabla' : 'ver tabla'">ver tabla</span>
      </button>
      <div data-show="$${sig}" style="display:none" class="mt-2">${table}</div>
    </div>
  </div>`;
function prosa(txt) {
  if (!txt) return "";
  return String(txt).split(/\n\s*\n/).map((p) => `<p class="text-sm mt-2" style="color:var(--text-2)">${md(p.trim())}</p>`).join("");
}
function lista(items, ordered = false) {
  if (!items || !items.length) return "";
  const tag = ordered ? "ol" : "ul";
  return `<${tag} class="mt-2 pl-5 ${ordered ? "list-decimal" : "list-disc"}">${items.map((t) => `<li class="text-sm mt-1.5" style="color:var(--text-2)">${md(t)}</li>`).join("")}</${tag}>`;
}
// Contacto: qué canal hay. Tener fila en el CRM no es tener con qué llamar.
function contacto(r) {
  const e = !!r.email, t = !!r.phone;
  if (!r.en_crm && r.en_crm !== "t") return `<span class="badge badge-neg" title="Sin fila en el CRM">sin CRM</span>`;
  if (!e && !t) return `<span class="badge badge-neg" title="Ni correo ni teléfono en el CRM">sin canal</span>`;
  if (!e) return `<span class="badge badge-cau" title="Solo teléfono">solo tel.</span>`;
  if (!t) return `<span class="badge badge-cau" title="Solo correo">solo correo</span>`;
  return `<span class="badge badge-pos">correo + tel.</span>`;
}

function filaAlumno(r) {
  return [
    `<span class="font-semibold">${escape(r.alumno || "—")}</span><br><span class="text-xs" style="color:var(--text-3)">${escape(r.programa || "")} · desde ${escape(String(r.inicio || "").slice(0, 10))}</span>`,
    `<span class="tabular-nums font-semibold" style="color:${TONE.neg}">${usd(r.pendiente)}</span><br><span class="text-xs" style="color:var(--text-3)">${num(r.vencidas)} cuota(s)</span>`,
    `<span class="tabular-nums">${num(r.dias_mora)} d</span>`,
    `<span class="tabular-nums">${num(r.pagadas)}/${num(r.cuotas)} · ${usd(r.cobrado)}</span><br><span class="text-xs" style="color:var(--text-3)">se frenó en la ${num(r.freno)}</span>`,
    contacto(r),
    `<span class="text-xs">${escape(r.closer || "—")}</span>`,
  ];
}
const HEAD_ALUMNOS = ["Alumno", "Pendiente", "Mora", "Pagó", "Contacto", "Closer"];

function render(ui) {
  const p = ui.params || {};
  const texto = p.texto || {};
  const src = ui.source || "cohorte_mora";
  const base = { project: p.project, desde: p.desde, hasta: p.hasta };
  let rows = [], ctx = [], err = "";
  try {
    rows = fetchSource(src, base).rows || [];
    ctx = fetchSource(src, { ...base, contexto: true }).rows || [];
  } catch (e) {
    err = e.message;
  }
  const sum = (rs, k) => rs.reduce((a, r) => a + n0(r[k]), 0);
  const N = rows.length;
  const pendiente = sum(rows, "pendiente"), cobrado = sum(rows, "cobrado"), vencidas = sum(rows, "vencidas");
  const moraProm = N ? sum(rows, "dias_mora") / N : 0;
  const alumnosCohorte = ctx.filter((c) => c.es_la_cohorte === true || c.es_la_cohorte === "t").reduce((a, c) => a + n0(c.alumnos), 0);
  const sinCanal = rows.filter((r) => !r.email && !r.phone).length;
  const soloUno = rows.filter((r) => (!!r.email) !== (!!r.phone)).length;
  const desdeCero = rows.filter((r) => n0(r.pagadas) === 0).length;

  // --- dónde se frena: cuota en la que paró cada uno ---
  const frenoMap = new Map();
  for (const r of rows) frenoMap.set(n0(r.freno), (frenoMap.get(n0(r.freno)) || 0) + 1);
  const frenos = [...frenoMap.entries()].sort((a, b) => a[0] - b[0]);
  const frenoSpec = frenos.length ? { kind: "bar", labels: frenos.map((f) => `cuota ${f[0]}`), series: [{ label: "Alumnos que se frenaron ahí", data: frenos.map((f) => f[1]) }], sort: "none" } : null;
  const enCuota2 = frenoMap.get(2) || 0;

  // --- contexto por cohorte ---
  const ctxSpec = ctx.length ? { kind: "bar", labels: ctx.map((c) => c.cohorte), series: [{ label: "% de alumnos en mora", data: ctx.map((c) => n0(c.pct)) }], sort: "none" } : null;
  const tCtx = tbl(["Cohorte", "Alumnos", "En mora", "%", ""], ctx.map((c) => {
    const es = c.es_la_cohorte === true || c.es_la_cohorte === "t";
    const joven = n0(c.pct) < 25 && c.cohorte >= "2026-07";
    return [
      `<span class="tabular-nums ${es ? "font-semibold" : ""}">${escape(c.cohorte)}</span>`,
      `<span class="tabular-nums">${num(c.alumnos)}</span>`,
      `<span class="tabular-nums">${num(c.en_mora)}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${joven ? TONE.muted : n0(c.pct) >= 50 ? TONE.neg : TONE.cau}">${num(c.pct)} %</span>`,
      es ? `<span class="badge badge-brand">esta cohorte</span>` : joven ? `<span class="text-xs" style="color:var(--text-3)">apenas llegó a la cuota 1 — no comparable</span>` : "",
    ];
  }));

  // --- segmentos: lo curado + lo vivo ---
  const segDefs = texto.segmentos || {};
  const segCards = SEG_ORDER.map((s) => {
    const rs = rows.filter((r) => r.segmento === s);
    const def = segDefs[s] || {};
    const pend = sum(rs, "pendiente"), dias = rs.length ? sum(rs, "dias_mora") / rs.length : 0;
    return `<article class="card card-pad mb-4">
      <header class="flex items-start gap-3 flex-wrap">
        <span class="badge ${SEG_BADGE[s]} shrink-0">${escape(s)}</span>
        <div class="min-w-0 flex-1">
          <h3 class="text-base font-semibold" style="color:var(--text-1)">${escape(def.nombre || s)}</h3>
          <p class="text-xs mt-0.5" style="color:var(--text-3)">${escape(def.regla || "")}</p>
        </div>
        <div class="text-right shrink-0">
          <div class="text-lg font-bold tabular-nums" style="color:var(--text-1)">${num(rs.length)} <span class="text-xs font-normal" style="color:var(--text-3)">alumno(s)</span></div>
          <div class="text-xs tabular-nums" style="color:var(--text-3)">${usd(pend)} · ${num(dias)} d promedio · ${pendiente ? num((100 * pend) / pendiente) : 0} % del pendiente</div>
        </div>
      </header>
      ${def.diagnostico ? `<p class="text-sm mt-3" style="color:var(--text-2)">${md(def.diagnostico)}</p>` : ""}
      <div class="grid gap-3 mt-3" style="grid-template-columns:repeat(auto-fit,minmax(14rem,1fr))">
        ${def.accion ? `<div><div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">Acción</div>${Array.isArray(def.accion) ? lista(def.accion, true) : `<p class="text-sm mt-1" style="color:var(--text-2)">${md(def.accion)}</p>`}</div>` : ""}
        ${def.responsable ? `<div><div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">Responsable</div><p class="text-sm mt-1" style="color:var(--text-2)">${md(def.responsable)}</p></div>` : ""}
        ${def.fecha ? `<div><div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">Cuándo</div><p class="text-sm mt-1" style="color:var(--text-2)">${md(def.fecha)}</p></div>` : ""}
      </div>
      ${def.ojo ? `<div class="alert alert-brand text-sm mt-3">${md(def.ojo)}</div>` : ""}
      <div class="mt-3" data-signals="{show${s}:${rs.length <= 4}}">
        <button data-on:click="$show${s}=!$show${s}" class="text-xs" style="color:var(--text-brand)">
          <span data-text="$show${s} ? 'ocultar la lista' : 'ver los ${rs.length} alumnos'">ver los ${rs.length} alumnos</span>
        </button>
        <div data-show="$show${s}" class="mt-2">${tbl(HEAD_ALUMNOS, rs.map(filaAlumno))}</div>
      </div>
    </article>`;
  }).join("");

  // --- por closer (señalamiento, no acusación) ---
  const closerMap = new Map();
  for (const r of rows) { const k = r.closer || "— (sin closer resuelto)"; const o = closerMap.get(k) || { n: 0, pend: 0 }; o.n++; o.pend += n0(r.pendiente); closerMap.set(k, o); }
  const tCloser = tbl(["Closer", "Alumnos en mora", "Pendiente"], [...closerMap.entries()].sort((a, b) => b[1].pend - a[1].pend).map(([k, v]) => [
    `<span>${escape(k)}</span>`, `<span class="tabular-nums">${num(v.n)}</span>`, `<span class="tabular-nums">${usd(v.pend)}</span>`,
  ]));

  const metricas = (texto.metricas || []).map((m) => [`<span class="font-semibold">${md(m.metrica)}</span>`, `<span>${md(m.como)}</span>`, `<span class="tabular-nums">${md(m.corte)}</span>`]);
  const estado = texto.estado || "BORRADOR — pendiente de la aprobación de Lorenzo (Loro)";

  return `<section id="pane" class="flex-1 p-6 overflow-auto">
  <div class="max-w-6xl mx-auto">
    <div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">${escape(ui.name)}</h1>
      <span class="badge badge-neutral">${escape(String(p.project || "—"))}</span>
      <span class="badge badge-neutral">cohorte ${escape(String(p.desde || ""))} → ${escape(String(p.hasta || ""))}</span>
      <span class="badge badge-cau" title="La aprobación es una atestación humana; hasta entonces esto es un borrador">${escape(estado)}</span>
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs" style="color:var(--text-brand)">abrir solo ↗</a>
    </div>
    <p class="mt-1 text-sm" style="color:var(--text-3)">${escape(texto.subtitulo || "Quiénes de la cohorte no están pagando, dónde se frenaron, y qué se hace con cada segmento. Las cifras se recalculan al abrir; el plan es el del documento.")}</p>
    ${err ? `<div class="alert alert-neg text-sm mt-4">${escape(err)}</div>` : ""}

    <div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">
      ${kpi("En mora", `${num(N)}${alumnosCohorte ? ` <span class="text-base font-normal" style="color:var(--text-3)">de ${num(alumnosCohorte)}</span>` : ""}`, { tone: "neg", sub: alumnosCohorte ? `${num((100 * N) / alumnosCohorte)} % de la cohorte` : "", title: "Alumnos con al menos una cuota vencida sin pagar" })}
      ${kpi("Pendiente vencido", usd(pendiente), { tone: "neg", sub: `${num(vencidas)} cuotas vencidas` })}
      ${kpi("Ya cobrado a esos mismos", usd(cobrado), { tone: "pos", sub: "ninguno dejó de pagar desde el principio", title: `Alumnos que nunca pagaron una cuota: ${desdeCero}` })}
      ${kpi("Mora promedio", `${num(moraProm)} d`, { sub: "desde el vencimiento más viejo de cada uno" })}
      ${kpi("Se frenaron en la cuota 2", num(enCuota2), { tone: "cau", sub: N ? `${num((100 * enCuota2) / N)} % — justo después del primer mes` : "" })}
      ${kpi("Sin canal de contacto", num(sinCanal), { tone: sinCanal ? "neg" : "pos", sub: `${num(soloUno)} más con un solo canal`, title: "Tener fila en el CRM no es tener con qué llamar" })}
    </div>

    ${texto.hallazgo ? `${section("Qué se encontró", "")}<div class="card card-pad">${prosa(texto.hallazgo)}</div>` : ""}

    ${section("Dónde se rompe", "en qué cuota se frenó cada alumno — la mitad, justo después de recibir el primer mes")}
    ${chartCard(frenoSpec, "showfreno", tbl(["Se frenó en la cuota", "Alumnos"], frenos.map((f) => [`<span class="tabular-nums">${f[0]}</span>`, `<span class="tabular-nums">${f[1]}</span>`])))}

    ${section("El contexto que cambia la lectura", "% de alumnos en mora por cohorte de ingreso — feb–mar no es una cohorte mala, es una cohorte normal")}
    ${chartCard(ctxSpec, "showctx", tCtx)}
    ${texto.contexto ? `<div class="card card-pad mt-3">${prosa(texto.contexto)}</div>` : ""}

    ${section("Segmentos y acciones", texto.criterio_segmentos || "criterio de corte: días de mora (desde el vencimiento) y proporción del plan pagada")}
    ${segCards}

    ${metricas.length ? `${section("Métrica de éxito", texto.metricas_nota || "")}${tbl(["Métrica", "Cómo se mide", "Corte"], metricas)}${texto.metas ? `<div class="card card-pad mt-3"><div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">Metas propuestas — a confirmar por Lorenzo</div>${lista(texto.metas)}</div>` : ""}` : ""}

    ${section("Por closer", "señalamiento, no acusación: hay que cruzarlo contra cuántos vendió cada uno")}
    ${tCloser}

    ${texto.causa_raiz && texto.causa_raiz.length ? `${section("La mitad que no es cobranza", "")}<div class="card card-pad">${lista(texto.causa_raiz, true)}</div>` : ""}

    ${texto.falta && texto.falta.length ? `${section("Lo que falta antes de ejecutar", "")}<div class="alert alert-brand text-sm">${lista(texto.falta)}</div>` : ""}

    <p class="mt-10 text-xs" style="color:var(--text-3)">
      ${escape(texto.pie || "Cohorte = fecha de inicio del plan. En mora = al menos una cuota vencida sin pagar; los días se cuentan desde el vencimiento, nunca desde el estado de la cuota (que jamás marca «vencida»). Segmentos: S1 ≤ 30 días · S2 ≤ 90 días · S3 pagó ≥ 50 % de sus cuotas · S4 el resto. Las cifras se recalculan al abrir.")}
    </p>
  </div>
  </section>`;
}

module.exports = {
  id: "plan-reactivacion",
  manifest: { consumes: "rows", overridable: [] },
  render,
};
