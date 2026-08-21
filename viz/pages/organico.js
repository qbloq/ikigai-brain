// organico page — EL EMBUDO ORGÁNICO: los leads del CRM que no llegaron por
// pauta, por canal de entrada (serie de YouTube y su módulo, lead magnets,
// survey orgánico, VSL sin pauta, masterclass, low ticket, aplicación premium,
// referidos), con su conversión y caja, contra la pauta de MARCA del mismo mes
// (follow-me / seguidores / video). Hueco #3 del contraste con el dashboard
// comercial (Kaizen 2026-08-20). Fuente `embudo_organico` (bash/metrics/organico.sh).
//
// Lo que esta página NO dice y lo declara: no cuenta DMs ni setters de
// Instagram. ManyChat aparece solo como MAPA del flujo (sus tags), porque su
// API no da conteos ni llave con el CRM (medido 2026-08-21). «Orgánico» es «no
// pagado», no «llegó solo»: roas_vs_marca es heurístico y se etiqueta así.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");
const { chartEl } = require("../blocks/charts");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };
const CANAL = {
  serie_youtube: ["Serie de YouTube", "formularios «Form serie YT Mn» y tags moduloNyt — el lead que vio el módulo y llenó el form"],
  lead_magnet: ["Lead magnets", "guías/videos descargables (formularios «lead magnet n», tags leadmagnetN)"],
  survey_organico: ["Survey orgánico", "el survey de calificación por la vía orgánica (bio, DMs, referidos)"],
  survey_vsl_sin_pauta: ["VSL sin pauta", "el survey del embudo pagado, pero sin campaña: directo/orgánico a la misma página"],
  masterclass: ["Masterclass", "registro a masterclass"],
  low_ticket: ["Low ticket", "form low ticket / payment_link / tag lt"],
  aplicacion_premium: ["Aplicación premium", "aplicación a Premium Mastermind/Academy, calendario, llamada de claridad, setter"],
  referido_bala: ["Referido (Bala)", "survey «David Bala»"],
  sin_formulario: ["Sin formulario", "contacto creado sin form de entrada (CRM UI, manual, pago directo)"],
  otro_formulario: ["Otro formulario", "form que el normalizador no reconoce"],
};

function num(v) { if (v == null || v === "") return "—"; const n = Number(v); return Number.isNaN(n) ? escape(String(v)) : n.toLocaleString("es-CO"); }
function usd(v) { if (v == null || v === "") return "—"; const n = Number(v); return Number.isNaN(n) ? escape(String(v)) : "$" + Math.round(n).toLocaleString("es-CO"); }
function pct(v) { return v == null ? "—" : `${Number(v).toLocaleString("es-CO")}%`; }
function xf(v) { return v == null ? "—" : `${Number(v).toLocaleString("es-CO")}x`; }

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
function tbl(headers, rows, { empty = "Sin datos." } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows.map((cells) => `<tr>${cells.map((c) => `<td class="align-top">${c}</td>`).join("")}</tr>`).join("");
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl"><thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`;
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
function tasaTone(v) { if (v == null) return TONE.muted; const n = Number(v); return n >= 10 ? TONE.pos : n >= 5 ? TONE.brand : TONE.muted; }

function renderOrganico(ui) {
  const p = ui.params || {};
  let d = {}, err;
  try {
    const res = fetchSource(ui.source || "embudo_organico", p);
    d = Array.isArray(res.rows) ? res.rows[0] : res.rows;
  } catch (e) { err = e.message; }
  d = d || {};
  const m = d.meta || {}, r = d.resumen || {}, canales = d.canales || [], yt = d.serie_youtube || [], ses = d.sesiones || [], series = d.series || [], mc = d.manychat || {};

  // --- KPIs
  const cab = `
    ${kpi("Leads orgánicos", `${num(r.organicos)}<span class="text-sm" style="color:var(--text-3)">/${num(r.leads_total)}</span>`, { sub: `${pct(r.pct_organico)} de los leads del CRM en la ventana · ${num(r.pagados)} por pauta`, title: m.regla_organico || "" })}
    ${kpi("Planes (orgánico)", num(r.planes), { tone: Number(r.planes) > 0 ? "pos" : "brand", sub: `${num(r.won)} won en CRM · tasa a plan ${pct(r.tasa_plan)} (pagados: ${pct(r.tasa_plan_pagados)})`, title: m.regla_dinero || "" })}
    ${kpi("Caja orgánica", usd(r.cash), { tone: Number(r.cash) > 0 ? "pos" : "brand", sub: `contrato ${usd(r.contrato)} · pagados cobraron ${usd(r.cash_pagados)}`, title: "cuotas pagadas de los planes ≤60 d de los leads orgánicos de la ventana (a hoy)" })}
    ${kpi("Pauta de marca", usd(r.marca_usd), { sub: `${num(r.ads_marca)} anuncios de marca (follow-me · seguidores · video)${Number(r.marca_cop) > 0 ? ` · COP ${num(r.marca_cop)} aparte` : ""}`, title: m.regla_marca || "" })}
    ${kpi("Caja orgánica / marca", xf(r.roas_vs_marca), { tone: "cau", sub: r.costo_por_lead_organico_vs_marca != null ? `marca por lead orgánico ${usd(r.costo_por_lead_organico_vs_marca)} · heurístico` : "heurístico", title: "heurístico: el orgánico de hoy viene de seguidores de meses atrás y la pauta de marca no es su única causa — lee la dirección, no el número" })}`;

  // --- canales
  const tCanales = tbl(
    ["Canal", "Leads", "Won", "Planes", "Tasa a plan", "Contrato", "Caja", "Sesión (GHL)", "Formularios"],
    canales.map((c) => {
      const [nombre, desc] = CANAL[c.canal] || [c.canal, ""];
      return [
        `<span class="font-semibold" title="${escape(desc)}">${escape(nombre)}</span>`,
        `<span class="tabular-nums font-semibold">${num(c.leads)}</span>`,
        `<span class="tabular-nums">${num(c.won)}</span>`,
        `<span class="tabular-nums font-semibold">${num(c.planes)}</span>`,
        `<span class="tabular-nums font-semibold" style="color:${tasaTone(c.tasa_plan)}">${pct(c.tasa_plan)}</span>`,
        `<span class="tabular-nums">${usd(c.contrato)}</span>`,
        `<span class="tabular-nums font-semibold" style="color:${Number(c.cash) > 0 ? TONE.pos : "inherit"}">${usd(c.cash)}</span>`,
        `<span class="text-xs" style="color:var(--text-3)">${(c.sesiones || []).map((s) => `${escape(String(s.sesion))} ${num(s.n)}`).join(" · ")}</span>`,
        `<span class="text-xs" style="color:var(--text-3)">${(c.formularios || []).map((f) => `<span class="font-mono">${escape(String(f.form || "(vacío)"))}</span> ${num(f.n)}`).join(" · ")}</span>`,
      ];
    }),
    { empty: "Sin leads orgánicos en la ventana." }
  );

  // --- serie de YouTube por módulo
  const ytSpec = yt.length
    ? { kind: "bar", labels: yt.map((x) => `M${x.modulo}`), series: [{ label: "Leads por módulo", data: yt.map((x) => x.leads) }] }
    : null;
  const tYt = tbl(
    ["Módulo", "Leads", "Won", "Planes", "Caja"],
    yt.map((x) => [
      `<span class="font-semibold">M${escape(String(x.modulo))}</span>`,
      `<span class="tabular-nums">${num(x.leads)}</span>`,
      `<span class="tabular-nums">${num(x.won)}</span>`,
      `<span class="tabular-nums">${num(x.planes)}</span>`,
      `<span class="tabular-nums">${usd(x.cash)}</span>`,
    ])
  );

  // --- serie mensual: orgánico vs pagado
  const serieSpec = series.length
    ? { kind: "line", labels: series.map((s) => s.mes), series: [
        { label: "Leads orgánicos", data: series.map((s) => s.organicos) },
        { label: "Leads por pauta", data: series.map((s) => s.pagados) },
        { label: "Serie YouTube", data: series.map((s) => s.serie_youtube) },
      ] }
    : null;
  const tSerie = tbl(
    ["Mes", "Leads", "Orgánicos", "Pauta", "Serie YT", "Planes org.", "Caja org. (a hoy)", "Planes pauta", "Caja pauta (a hoy)", "Marca USD", "Adquisición USD", "Caja org./marca"],
    series.map((s) => [
      `<span class="font-semibold tabular-nums">${escape(s.mes)}</span>`,
      `<span class="tabular-nums">${num(s.leads)}</span>`,
      `<span class="tabular-nums font-semibold">${num(s.organicos)}</span>`,
      `<span class="tabular-nums">${num(s.pagados)}</span>`,
      `<span class="tabular-nums">${num(s.serie_youtube)}</span>`,
      `<span class="tabular-nums">${num(s.planes_organicos)}</span>`,
      `<span class="tabular-nums" style="color:${TONE.pos}">${usd(s.cash_organico)}</span>`,
      `<span class="tabular-nums">${num(s.planes_pagados)}</span>`,
      `<span class="tabular-nums">${usd(s.cash_pagado)}</span>`,
      `<span class="tabular-nums">${usd(s.marca_usd)}</span>`,
      `<span class="tabular-nums">${usd(s.adquisicion_usd)}</span>`,
      `<span class="tabular-nums" style="color:${TONE.cau}">${xf(s.roas_vs_marca)}</span>`,
    ])
  );

  // --- sesiones
  const tSes = tbl(
    ["Sesión registrada por GHL", "Leads", "Won", "Planes", "Caja"],
    ses.map((s) => [
      `<span class="font-semibold">${escape(String(s.sesion))}</span>`,
      `<span class="tabular-nums">${num(s.leads)}</span>`,
      `<span class="tabular-nums">${num(s.won)}</span>`,
      `<span class="tabular-nums">${num(s.planes)}</span>`,
      `<span class="tabular-nums" style="color:${Number(s.cash) > 0 ? TONE.pos : "inherit"}">${usd(s.cash)}</span>`,
    ])
  );

  // --- ManyChat: el mapa del flujo
  const mapa = (mc.mapa || []).map((t) => `<span class="badge badge-neutral mr-1 mb-1 inline-block">${escape(String(t))}</span>`).join("");
  const mcHtml = mc.disponible
    ? `<div class="card card-pad"><div class="mb-2">${mapa || "<span class='text-xs italic'>sin tags</span>"}</div><p class="text-xs" style="color:var(--text-3)">${escape(mc.nota || "")}</p></div>`
    : `<div class="alert"><p class="text-sm">ManyChat no disponible: ${escape(mc.error || "—")}</p></div>`;

  const body = err
    ? `<div class="alert mt-4" style="border-left:3px solid var(--neg-solid)"><p class="text-sm">${escape(err)}</p></div>`
    : `<div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">${cab}</div>
       ${section("Canales de entrada", "de dónde entran los leads no pagados — el formulario que llenaron (y sus tags), con la sesión que GHL registró al lado")}
       ${tCanales}
       <div class="grid gap-4 mt-4" style="grid-template-columns:repeat(auto-fit,minmax(22rem,1fr))">
         <div>${section("Serie de YouTube — por módulo", "qué escalón de la serie produce el lead")}${chartCard(ytSpec, "showyt", tYt)}</div>
         <div>${section("Sesión (GHL)", "cómo llegó al form: Social media = IG/YT, Referral = link compartido, Direct = escribió la URL")}${tSes}</div>
       </div>
       ${section("Serie mensual — orgánico vs pauta", `últimos ${num(m.meses)} meses · la caja de cada mes es la cobrada A HOY de esos leads: los meses recientes siguen cobrando`)}
       ${chartCard(serieSpec, "showserie", tSerie)}
       ${section("ManyChat — el mapa del flujo de Instagram", `${mc.disponible ? `conectado · ${num((mc.mapa || []).length)} tags` : "sin conexión"} · el recorrido nuevo seguidor → quiz → asesoría → serie YT → lead magnets → grupo VIP · el API no da conteos (ver nota)`)}
       ${mcHtml}
       ${(d.sin_instrumentar || []).length ? `<p class="mt-4 text-xs" style="color:var(--text-3)"><b>Sin instrumentar:</b> ${d.sin_instrumentar.map((x) => escape(x)).join(" · ")}</p>` : ""}`;

  // OJO: `id="pane"` NO es decorativo — ver la nota en pages/lead-score.js.
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
  <div class="max-w-7xl mx-auto">
    <div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">Embudo orgánico</h1>
      <span class="badge badge-neutral">${escape(String(p.project || m.proyecto || "—"))}</span>
      <span class="badge badge-neutral">${escape(String(m.desde || "…"))} → ${escape(String(m.hasta || "hoy"))}</span>
      ${m.generado ? `<span class="text-xs" style="color:var(--text-3)">generado ${escape(m.generado)}</span>` : ""}
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs" style="color:var(--text-brand)">abrir solo ↗</a>
    </div>
    <p class="mt-1 text-sm" style="color:var(--text-3)">
      Los leads del CRM que <strong>no</strong> llegaron por pauta (sin campaña ni en la atribución nativa de GHL ni en el utm del formulario), por canal de entrada, con su conversión y caja, al lado de la <strong>pauta de marca</strong> del mismo mes. «Orgánico» = no pagado, no «llegó solo».
    </p>
    ${body}
    <p class="mt-10 text-xs" style="color:var(--text-3)">
      Fuente: <code>bash/metrics/organico.sh --project "${escape(String(p.project || ""))}"</code> · ${escape(m.regla_canal || "")} · ${escape(m.regla_marca || "")}
    </p>
  </div>
  </section>`;
}

module.exports = {
  id: "organico",
  manifest: { consumes: "object", overridable: ["project", "from", "to", "meses"] },
  render: renderOrganico,
};
