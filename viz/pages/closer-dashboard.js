// closer-dashboard page — el dashboard de UN closer, desde el único objeto que
// emite bash/calls/closer_dashboard.sh. Es la vista del Director Comercial:
// la capa de OPERACIÓN de docs/lead-score.md §5 (bandas, BANT, cola de
// seguimiento, cash real), que por política el closer NO ve — el closer ve su
// cola ordenada, las respuestas textuales y su coaching, nunca el número.
//
// Dos mitades deliberadas, en este orden:
//   la llamada  lo que el analizador midió (conversión canónica, tramos BANT,
//               la cola de BANT ≥ 81 que se enfría, coaching, objeciones)
//   la plata    lo que de verdad pasó (payment_plans.user_id ES el closer;
//               installments es la verdad del dinero; su comisión)
// El callStatus del reporte y el cash real son fuentes distintas — mostrarlas
// juntas es lo que permite verles la costura.

const { fetchSource } = require("../lib/datasources");
const { escape, jsStr } = require("../lib/kit");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };

function num(v) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  return Number.isNaN(n) ? escape(String(v)) : n.toLocaleString("es-CO");
}
const usd = (v) => (v == null ? "—" : "$" + Math.round(Number(v)).toLocaleString("en-US"));

function kpi(label, value, { tone = "brand", sub = "", title = "" } = {}) {
  return `<div class="card card-pad kpi"${title ? ` title="${escape(title)}"` : ""}>
    <span class="kpi-label">${escape(label)}</span>
    <span class="kpi-value tabular-nums" style="color:${TONE[tone] || TONE.brand}">${value}</span>
    ${sub ? `<span class="kpi-foot">${escape(sub)}</span>` : ""}
  </div>`;
}

function section(title, hint) {
  return `<div class="flex items-baseline gap-3 mt-10 mb-3 flex-wrap">
    <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(title)}</h2>
    ${hint ? `<span class="text-xs" style="color:var(--text-3)">${escape(hint)}</span>` : ""}
  </div>`;
}

// Tabla con una columna porcentual pintada como barra (el idioma de la página
// lead-score, su vecina en la capa del DC): el tramo que discrimina se ve de
// un vistazo, sin leer decimales.
function tbl(headers, rows, { empty = "Sin datos.", barCol = null, barMax = 100 } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows
    .map((cells) =>
      `<tr>${cells
        .map((c, i) => {
          if (barCol !== null && i === barCol) {
            const pct = Number(c) || 0;
            const w = Math.max(1, Math.min(100, (pct / barMax) * 100));
            return `<td class="whitespace-nowrap"><div class="flex items-center gap-2">
              <span class="tabular-nums font-semibold" style="min-width:3.2rem;color:${pct >= 20 ? TONE.pos : pct > 0 ? TONE.cau : TONE.muted}">${pct.toFixed(1)}%</span>
              <span style="display:block;height:6px;border-radius:3px;width:${w}%;min-width:2px;background:${pct >= 20 ? "var(--pos-solid)" : "var(--cau-solid)"}"></span>
            </div></td>`;
          }
          return `<td class="align-top">${c}</td>`;
        })
        .join("")}</tr>`
    )
    .join("");
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`;
}

const list = (items) =>
  (Array.isArray(items) ? items : items ? [items] : [])
    .map((x) => `<li class="mb-1">${escape(String(x))}</li>`)
    .join("");

function coachCard(c) {
  const score = c.score == null ? "—" : Number(c.score).toLocaleString("es-CO");
  const tone = c.score >= 7 ? TONE.pos : c.score >= 5 ? TONE.cau : TONE.neg;
  const col = (label, items, ink) =>
    (items && (Array.isArray(items) ? items.length : true))
      ? `<div class="min-w-0"><p class="text-[11px] font-semibold uppercase mb-1" style="color:${ink};letter-spacing:var(--tr-micro)">${escape(label)}</p>
         <ul class="text-xs list-disc ml-4" style="color:var(--text-2)">${list(items)}</ul></div>`
      : "";
  return `<div class="card card-pad">
    <div class="flex items-baseline gap-2 flex-wrap mb-2">
      <span class="font-semibold text-sm" style="color:var(--text-1)">${escape(c.lead || "—")}</span>
      <span class="text-xs" style="color:var(--text-3)">${escape(c.fecha || "")} · ${escape(c.resultado || "")} · <code>${escape(c.id || "")}</code></span>
      <span class="ml-auto kpi-value text-base tabular-nums" style="color:${tone}">${score}<span class="text-xs" style="color:var(--text-3)">/10</span></span>
    </div>
    <div class="grid gap-3" style="grid-template-columns:repeat(auto-fit,minmax(14rem,1fr))">
      ${col("Fortalezas", c.fortalezas, TONE.pos)}
      ${col("Áreas de mejora", c.mejoras, TONE.cau)}
      ${col("Coaching", c.coaching, TONE.brand)}
    </div>
  </div>`;
}

function renderCloserDashboard(ui) {
  let d = {};
  let err;
  try {
    const { rows } = fetchSource(ui.source || "closer_dashboard", ui.params || {});
    d = rows[0] || {};
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto">
      <div class="alert alert-neg">${escape(err)}</div></section>`;
  }

  const k = d.kpis || {};
  const vn = d.ventas || {};
  const per = d.periodo || {};
  const closers = d.closers || [];
  const cur = d.closer || "";

  // Selector + ventana. Si `closer` viene FORZADO por identidad (publicador:
  // ui._locked), el dropdown no se pinta — chip fijo; y el re-fetch no emite
  // el param (el servidor lo fuerza igual: el chip es UX, no seguridad).
  const bloqueado = (ui._locked || []).includes("closer");
  const reget = bloqueado
    ? `@get('/ui/${escape(ui.id)}?from='+$cdFrom+'&to='+$cdTo)`
    : `@get('/ui/${escape(ui.id)}?closer='+encodeURIComponent($cdCloser)+'&from='+$cdFrom+'&to='+$cdTo)`;
  const opts = closers
    .map((c) => {
      const parts = [c.llamadas != null ? `${c.llamadas} llamadas` : null, c.ventas != null ? `${c.ventas} ventas` : null]
        .filter(Boolean)
        .join(" · ");
      return `<option value="${escape(c.closer)}"${c.closer === cur ? " selected" : ""}>${escape(c.closer)}${parts ? ` — ${escape(parts)}` : ""}</option>`;
    })
    .join("");
  const selector = bloqueado
    ? `<span class="badge badge-brand text-sm">${escape(cur || "—")}</span>`
    : `<select data-bind="cdCloser" data-on:change="${reget}" data-indicator:loadingcloser class="select w-auto font-medium">${opts}</select>`;
  const signals = bloqueado
    ? `{cdFrom:${escape(jsStr(per.from || ""))},cdTo:${escape(jsStr(per.to || ""))}}`
    : `{cdCloser:${escape(jsStr(cur))},cdFrom:${escape(jsStr(per.from || ""))},cdTo:${escape(jsStr(per.to || ""))}}`;
  const controls = `<div class="flex flex-wrap items-center gap-3 mt-4" data-signals="${signals}">
    ${selector}
    <input type="date" data-bind="cdFrom" data-on:change="${reget}" data-indicator:loadingcloser class="input w-auto" />
    <span style="color:var(--text-3)">~</span>
    <input type="date" data-bind="cdTo" data-on:change="${reget}" data-indicator:loadingcloser class="input w-auto" />
    <span class="text-xs" style="color:var(--text-3)">sin fechas = toda la historia</span>
  </div>`;

  const kpisLlamada = `
    ${kpi("Llamadas analizadas", num(k.llamadas), { sub: `${num(k.con_bant)} con BANT real`, title: "Sus llamadas con reporte en la ventana; el BANT en cero literal (sin transcript) no califica" })}
    ${kpi("Conversión", (k.conv_pct ?? "—") + (k.conv_pct != null ? "%" : ""), { tone: "pos", sub: `${num(k.convirtio)} de ${num(k.con_bant)}`, title: "Resultado canónico: ganada + compromiso (el cierre real lo sella la primera cuota)" })}
    ${kpi("Score de desempeño", k.score_prom != null ? `${num(k.score_prom)}<span class="text-sm" style="color:var(--text-3)">/10</span>` : "—", { title: "Promedio del finalCloserEvaluation del analizador — esto SÍ lo ve el closer" })}
    ${kpi("BANT promedio", num(k.bant_prom), { title: "Calidad promedio de los leads que le llegaron (0-100, ceros excluidos)" })}
    ${kpi("Prob. de cierre prom.", k.prob_prom != null ? num(k.prob_prom) + "%" : "—", { title: "closingProbability promedio del analizador" })}
    ${kpi("Cola sin trabajar", num(k.cola_n), { tone: k.cola_n > 0 ? "neg" : "pos", sub: "BANT ≥ 81 en seguimiento", title: "Leads del tramo que convierte ~39% que se están enfriando en su cola" })}`;

  const kpisPlata = `
    ${kpi("Ventas (planes)", num(vn.planes), { tone: "pos", title: "payment_plans a su nombre en la ventana (por fecha de inicio)" })}
    ${kpi("Venta programada", usd(vn.venta_usd), { tone: "pos", sub: "USD", title: "Suma del monto original de sus planes" })}
    ${kpi("Cash cobrado", usd(vn.cash_usd), { tone: "pos", sub: "USD · installments pagadas", title: "La verdad del dinero: cuotas efectivamente pagadas de sus planes" })}
    ${kpi("Comisiones", usd(vn.comisiones_usd), { tone: "cau", sub: `${usd(vn.comisiones_pend_usd)} sin pagar`, title: "commission_payouts a su nombre (pendiente + aprobada + pagada)" })}`;

  const tTramos = tbl(
    ["Tramo BANT", "Llamadas", "Convirtió", "Conversión", "En seguimiento"],
    (d.tramos || []).map((t) => [
      `<span class="font-semibold tabular-nums">${escape(t.tramo)}</span>`,
      `<span class="tabular-nums">${num(t.llamadas)}</span>`,
      `<span class="tabular-nums">${num(t.convirtio)}</span>`,
      t.conv_pct,
      `<span class="tabular-nums">${num(t.en_seguimiento)}</span>`,
    ]),
    { barCol: 3, barMax: 40, empty: "Sin llamadas con BANT en la ventana." }
  );

  const tCola = tbl(
    ["BANT", "Fecha", "Lead", "Programa", "Proyecto", "Estado", "Llamada"],
    (d.cola || []).map((c) => [
      `<span class="tabular-nums font-bold" style="color:${TONE.neg}">${num(c.bant)}</span>`,
      `<span class="tabular-nums text-xs">${escape(c.fecha || "")}</span>`,
      `<span class="font-medium">${escape(c.lead || "—")}</span>`,
      `<span class="text-xs">${escape(String(c.programa || "").slice(0, 60))}</span>`,
      `<span class="text-xs">${escape(c.proyecto || "—")}</span>`,
      `<span class="badge badge-neutral">${escape(c.status || "—")}</span>`,
      `<code class="text-xs">${escape(c.id || "")}</code>`,
    ]),
    { empty: "La cola está vacía — nada de BANT alto se está enfriando." }
  );

  const tObj = tbl(
    ["Fecha", "Lead", "Estado", "Objeción", "Respuesta del closer", "Sugerencia IA"],
    (d.objeciones || []).map((o) => [
      `<span class="tabular-nums text-xs">${escape(o.fecha || "")}</span>`,
      `<span class="text-xs font-medium">${escape(o.lead || "—")}</span>`,
      `<span class="badge ${/overcome|superad/i.test(o.status || "") && !/not/i.test(o.status || "") ? "badge-pos" : "badge-neutral"}">${escape(o.status || "—")}</span>`,
      `<span class="text-xs">${escape(String(o.objecion || "").slice(0, 140))}</span>`,
      `<span class="text-xs" style="color:var(--text-2)">${escape(String(o.respuesta || "").slice(0, 140))}</span>`,
      `<span class="text-xs" style="color:var(--text-3)">${escape(String(o.sugerencia || "").slice(0, 140))}</span>`,
    ]),
    { empty: "Sin objeciones registradas en la ventana." }
  );

  const tVentas = tbl(
    ["Inicio", "Cliente", "Proyecto", "Monto", "Cobrado", "Estado", "Plan"],
    ((vn.recientes || [])).map((p) => [
      `<span class="tabular-nums text-xs">${escape(p.inicio || "")}</span>`,
      `<span class="font-medium">${escape(p.cliente || "—")}</span>`,
      `<span class="text-xs">${escape(p.proyecto || "—")}</span>`,
      `<span class="tabular-nums">${usd(p.monto)}</span>`,
      `<span class="tabular-nums" style="color:${(p.cobrado || 0) >= (p.monto || 0) ? TONE.pos : TONE.cau}">${usd(p.cobrado)}</span>`,
      `<span class="badge badge-neutral">${escape(p.estado || "—")}</span>`,
      `<code class="text-xs">${escape(p.id || "")}</code>`,
    ]),
    { empty: "Sin planes de pago a su nombre en la ventana." }
  );

  const coaching = (d.coaching || []).map(coachCard).join("") ||
    `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">Sin llamadas evaluadas en la ventana.</p>`;

  // id="pane" NO es decorativo: el SSE parchea por id (ver pages/lead-score.js).
  return `<section id="pane" class="flex-1 relative overflow-auto p-6">
    <style>#cd-loading{opacity:0;transition:opacity .2s ease}#cd-loading.on{opacity:1}</style>
    <div id="cd-loading" data-class:on="$loadingcloser" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
      <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
    </div>
    <div class="max-w-6xl mx-auto">
      <div class="flex items-baseline gap-3 flex-wrap">
        <h1 class="text-xl font-bold" style="color:var(--text-1)">${escape(ui.name || "Dashboard por closer")}</h1>
        <span class="badge badge-brand">${escape(cur || "—")}</span>
        <span class="badge badge-neutral">corte ${escape(d.corte || "—")}</span>
        <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs hover:underline" style="color:var(--text-brand)">abrir solo ↗</a>
      </div>
      <p class="mt-1 text-sm" style="color:var(--text-3)">
        La capa de operación de <code>docs/lead-score.md</code> §5 — para el Director Comercial.
        El closer no ve bandas ni BANT: ve su cola ordenada, las respuestas textuales y su coaching.
      </p>
      ${controls}

      ${section("La llamada", "lo que el analizador midió sobre sus llamadas con reporte")}
      <div class="grid gap-3" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">${kpisLlamada}</div>

      ${section("La plata", "lo que de verdad pasó — planes, cuotas cobradas y su comisión (todo USD)")}
      <div class="grid gap-3" style="grid-template-columns:repeat(auto-fit,minmax(13rem,1fr))">${kpisPlata}</div>

      ${section("Tramos BANT", "sus llamadas por banda de calificación — ceros (sin transcript) excluidos")}
      ${tTramos}

      ${section("Cola de seguimiento", `${num(k.cola_n)} llamadas de BANT ≥ 81 que quedaron en seguimiento y nunca cerraron — el dinero sobre la mesa`)}
      ${tCola}

      ${section("Ventas recientes", "sus últimos planes de pago, con lo efectivamente cobrado")}
      ${tVentas}

      ${section("Coaching por llamada", "la evaluación del analizador — la parte que SÍ es del closer")}
      <div class="grid gap-3" style="grid-template-columns:repeat(auto-fit,minmax(24rem,1fr))">${coaching}</div>

      ${section("Objeciones recientes", "cómo respondió y qué sugirió la IA — alimenta el protocolo de objeciones (S12.2)")}
      ${tObj}

      <p class="mt-10 text-xs" style="color:var(--text-3)">
        Fuente: <code>bash/calls/closer_dashboard.sh</code>. Resultado canónico y normalizaciones:
        <code>bash/calls/lead_profile.sh</code>. La política de visibilidad: <code>docs/lead-score.md</code> §5.
      </p>
    </div>
  </section>`;
}

module.exports = {
  id: "closer-dashboard",
  manifest: { consumes: "object", overridable: ["closer", "project", "from", "to"] },
  render: renderCloserDashboard,
};
