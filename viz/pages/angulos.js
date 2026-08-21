// angulos page — ÁNGULOS GANADORES → TITULARES, desde el único objeto que emite
// bash/ads/angulos.sh: campañas por caja (atribución UTM), familias de copy de
// anuncio (el ángulo con que se compró el clic) y las landings del VSL con el
// H1 que muestran HOY, leído en vivo.
//
// Nació de la alineación DG 2026-08-19 (meeting b3f06835): «testear titulares
// en la página del VSL para subir play rate y retención», con el insumo que la
// misma reunión definió — rastrear de qué campañas/anuncios salen los
// calificados y las ventas para validar los ángulos ganadores. La página pone
// los dos lados juntos: el ángulo que compra el clic y el titular que lo
// recibe. Si no coinciden, ese quiebre de message-match es la primera
// hipótesis del testeo.
//
// Los TITULARES PROPUESTOS son params del SPEC (`params.titulares`), no
// código ni dato: son copy curado (Cerebro + equipo), versionado en git, y se
// cambian re-publicando el spec — igual que las metas del embudo. El testeo
// se abre desde la conversación (bash/testeos/testeo_abrir.sh), nunca desde
// esta página: viz es el visor.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };

function num(v) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  return Number.isNaN(n) ? escape(String(v)) : n.toLocaleString("es-CO");
}
function usd(v) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  return Number.isNaN(n) ? escape(String(v)) : "$" + Math.round(n).toLocaleString("es-CO");
}
function pctf(v) {
  return v == null ? "—" : `${Number(v).toLocaleString("es-CO")}%`;
}
function xf(v) {
  return v == null ? "—" : `${Number(v).toLocaleString("es-CO")}×`;
}

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
function badge(s, kind = "neutral") {
  return `<span class="badge badge-${kind}" style="font-size:.65rem">${escape(s)}</span>`;
}
function tbl(headers, rows, { empty = "Sin datos." } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows.map((cells) => `<tr>${cells.map((c) => `<td class="align-top">${c}</td>`).join("")}</tr>`).join("");
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`;
}
function thumb(url, alt) {
  if (!url) return "";
  return `<img src="${escape(url)}" alt="${escape(alt || "")}" loading="lazy" referrerpolicy="no-referrer"
    style="width:2.6rem;height:3.2rem;object-fit:cover;border-radius:var(--r-sm,4px);background:var(--surface-2);flex:none">`;
}
function shQuote(s) {
  return "'" + String(s == null ? "" : s).replace(/'/g, "'\\''") + "'";
}

// ---------- landings: el titular vigente ----------
function landingCard(l, generado) {
  const h1 = l.h1
    ? `<blockquote class="text-lg font-semibold leading-snug" style="color:var(--text-1);border-left:3px solid var(--brand-solid);padding-left:.8rem;margin:.4rem 0">${escape(l.h1)}</blockquote>`
    : `<div class="alert alert-neutral text-sm">No se pudo leer el H1 en vivo${l.error ? ` (${escape(l.error)})` : ""}.</div>`;
  const extra = (l.h1_todos || []).slice(1);
  return `<div class="card card-pad" style="display:flex;flex-direction:column;gap:.5rem">
    <div class="flex items-center gap-2 flex-wrap">
      ${badge("titular vigente · leído en vivo " + (generado || ""), "brand")}
      <a class="text-xs underline" style="color:var(--text-brand)" href="${escape(l.url)}" target="_blank" rel="noopener">${escape(l.url.replace(/^https?:\/\//, ""))}</a>
    </div>
    ${h1}
    ${extra.length ? `<details class="text-xs" style="color:var(--text-3)"><summary>otros H1 de la página (${extra.length})</summary><ul class="list-disc ml-5 mt-1">${extra.map((x) => `<li>${escape(x)}</li>`).join("")}</ul></details>` : ""}
    ${l.title ? `<p class="text-xs" style="color:var(--text-3)">&lt;title&gt; ${escape(l.title)}</p>` : ""}
    <div class="flex gap-4 text-xs flex-wrap tabular-nums" style="color:var(--text-2)">
      <span><b>${usd(l.spend)}</b> pauta</span><span><b>${num(l.n_anuncios)}</b> anuncios</span>
      <span><b>${num(l.lpv)}</b> aterrizajes</span><span><b>${num(l.compras_pixel)}</b> compras pixel</span>
    </div>
    <p class="text-xs" style="color:var(--text-3)">campañas: ${(l.campanas || []).map((c) => escape(c)).join(" · ")}</p>
  </div>`;
}

// ---------- familias de copy ----------
function anguloCard(a, i, maxCash) {
  const share = maxCash > 0 && a.cash_estimado ? Math.round((a.cash_estimado / maxCash) * 100) : 0;
  const ads = (a.anuncios || []).slice(0, 12).map((x) => `
    <li class="flex items-center gap-2 py-1" style="border-top:1px solid var(--border-1)">
      ${thumb(x.miniatura, x.anuncio)}
      <div class="min-w-0 flex-1">
        <div class="text-xs truncate" title="${escape(x.anuncio || "")}">${escape(x.anuncio || "")} ${x.estado && x.estado !== "ACTIVE" ? badge(x.estado.toLowerCase()) : ""}</div>
        <div class="text-[.68rem] tabular-nums" style="color:var(--text-3)">${escape(x.campana || "")} · ${usd(x.spend)} · LPV ${num(x.lpv)} · hook ${pctf(x.hook_pct)} · hold ${pctf(x.hold_pct)} · compras px ${num(x.compras)}</div>
      </div></li>`).join("");
  return `<div class="card card-pad" style="display:flex;flex-direction:column;gap:.55rem">
    <div class="flex items-start gap-2">
      <span class="kpi-value tabular-nums" style="font-size:1.4rem;color:var(--text-3);line-height:1">${i + 1}</span>
      <div class="min-w-0 flex-1">
        <p class="font-semibold leading-snug" style="color:var(--text-1)">${escape(a.gancho || "(sin copy)")}</p>
        <div class="flex gap-1 flex-wrap mt-1">${a.titulo_anuncio ? badge("título: " + a.titulo_anuncio) : ""}${badge(`${a.n_anuncios} anuncio${a.n_anuncios === 1 ? "" : "s"}`)}</div>
      </div>
    </div>
    <div class="grid gap-x-4 gap-y-1 text-xs tabular-nums" style="grid-template-columns:repeat(2,minmax(0,1fr));color:var(--text-2)">
      <span>pauta <b>${usd(a.spend)}</b></span><span>aterrizajes <b>${num(a.lpv)}</b></span>
      <span>compras pixel <b>${num(a.compras_pixel)}</b> ${a.cpa_pixel != null ? `(CPA ${usd(a.cpa_pixel)})` : ""}</span>
      <span>hook <b>${pctf(a.hook_pct)}</b> · hold <b>${pctf(a.hold_pct)}</b></span>
      <span>leads ~<b>${num(a.leads_estimados == null ? null : Math.round(a.leads_estimados))}</b> ${badge("est.")}</span>
      <span>caja ~<b style="color:${TONE.pos}">${usd(a.cash_estimado)}</b> ${badge("est.")} ${a.roas_real_estimado != null ? `ROAS ~${xf(a.roas_real_estimado)}` : ""}</span>
    </div>
    <div style="height:4px;border-radius:2px;background:var(--surface-2);overflow:hidden"><div style="width:${share}%;height:100%;background:var(--brand-solid)"></div></div>
    <p class="text-[.68rem]" style="color:var(--text-3)">campañas: ${(a.campanas || []).map((c) => escape(c)).join(" · ") || "—"}</p>
    <details class="text-xs"><summary style="color:var(--text-brand);cursor:pointer">copy completo + anuncios</summary>
      <pre class="mt-2 whitespace-pre-wrap text-xs" style="font-family:inherit;color:var(--text-2);background:var(--surface-2);padding:.6rem;border-radius:var(--r-md,8px)">${escape(a.cuerpo || "—")}</pre>
      <ul class="mt-2">${ads}</ul>
      ${(a.anuncios || []).length > 12 ? `<p class="text-[.68rem] mt-1" style="color:var(--text-3)">+${a.anuncios.length - 12} anuncios más</p>` : ""}
    </details>
  </div>`;
}

// ---------- titulares propuestos (params del spec) ----------
function titularCard(t, i, ctx) {
  const cmd = `bash/testeos/testeo_abrir.sh --project ${shQuote(ctx.project)} --step titular --variable ${shQuote("titular VSL → " + (t.texto || "").slice(0, 70))} --metrica ${ctx.metrica}${t.hipotesis ? ` --hipotesis ${shQuote(t.hipotesis)}` : ""}`;
  return `<div class="card card-pad" style="display:flex;flex-direction:column;gap:.5rem">
    <div class="flex items-start gap-2">
      <span class="kpi-value tabular-nums" style="font-size:1.4rem;color:var(--text-brand);line-height:1">T${i + 1}</span>
      <div class="min-w-0 flex-1">
        <p class="text-lg font-bold leading-snug" style="color:var(--text-1)">${escape(t.texto || "")}</p>
        ${t.sub ? `<p class="text-sm mt-1" style="color:var(--text-2)">${escape(t.sub)}</p>` : ""}
      </div>
    </div>
    <div class="flex gap-1 flex-wrap">${t.angulo ? badge("ángulo: " + t.angulo, "brand") : ""}${t.estado ? badge(t.estado) : ""}</div>
    ${t.evidencia ? `<p class="text-xs" style="color:var(--text-2)"><b>Evidencia:</b> ${escape(t.evidencia)}</p>` : ""}
    ${t.hipotesis ? `<p class="text-xs" style="color:var(--text-2)"><b>Hipótesis:</b> ${escape(t.hipotesis)}</p>` : ""}
    <details class="text-xs"><summary style="color:var(--text-brand);cursor:pointer">abrir el testeo con este titular (desde la conversación)</summary>
      <pre class="mt-2 whitespace-pre-wrap" style="color:var(--text-2);background:var(--surface-2);padding:.6rem;border-radius:var(--r-md,8px)">${escape(cmd)}</pre>
      <p class="mt-1" style="color:var(--text-3)">Publicar el titular en la página ANTES de abrir; el script congela el embudo en ese instante como línea base.</p>
    </details>
  </div>`;
}

function renderAngulos(ui) {
  const p = ui.params || {};
  const project = p.project || "David Guerrero";
  const metrica = p.metrica || "vsl.total.tasa_play";
  const titulares = Array.isArray(p.titulares) ? p.titulares : [];
  const { rows } = fetchSource(ui.source || "ad_angulos", { project, from: p.from, to: p.to, min_spend: p.min_spend });
  const d = rows[0] || {};
  const m = d.meta || {};
  const t = d.totales || {};
  const camps = d.campanas || [];
  const angulos = d.angulos || [];
  const landings = d.landings || [];

  // El testeo en curso del step titular — para que la página diga si ya hay uno.
  let testeos = [];
  let testeosErr = "";
  try {
    testeos = fetchSource("testeos", { project, step: "titular", limit: "0" }).rows || [];
  } catch (e) {
    testeosErr = String(e.message || e);
  }
  const enCurso = testeos.filter((x) => x.estado === "en_curso");
  const cerrados = testeos.filter((x) => x.estado !== "en_curso");

  const pctAtr = t.leads ? Math.round((t.leads_atribuidos / t.leads) * 100) : null;
  const kpis = [
    kpi("Pauta (USD)", usd(t.spend_usd), { sub: `${m.desde || ""} → ${m.hasta || ""}` }),
    kpi("Leads CRM", num(t.leads), { sub: pctAtr == null ? "" : `${num(t.leads_atribuidos)} con UTM (${pctAtr}%)`, tone: pctAtr != null && pctAtr < 60 ? "cau" : "brand" }),
    kpi("Planes (de leads de la ventana)", num(t.planes), { sub: `${num(t.ganadas)} won en CRM`, tone: "pos" }),
    kpi("Caja de esos planes", usd(t.cash), { tone: "pos", sub: "installments pagadas a hoy" }),
    kpi("CPL real", usd(t.cpl_real), { sub: "pauta USD / leads con UTM" }),
    kpi("CAC real", usd(t.cac_real), { sub: "pauta USD / planes", tone: t.cac_real != null && t.cac_real > 500 ? "cau" : "brand" }),
    kpi("ROAS real", xf(t.roas_real), { sub: "caja / pauta USD", tone: t.roas_real != null && t.roas_real < 2.5 ? "neg" : "pos" }),
  ].join("");

  // Campañas: ranking por caja; top-3 con pauta marcadas ganadoras.
  let rank = 0;
  const campRows = camps.map((c) => {
    const ganadora = !c.sin_atribucion && c.spend && (c.planes > 0 || c.ganadas > 0) && rank++ < 3;
    const name = `${escape(c.campana)} ${ganadora ? badge("ganadora", "pos") : ""} ${c.sin_atribucion ? badge("sin UTM", "neutral") : ""} ${c.alerta ? `<span title="${escape(c.alerta)}">${badge("UTM roto", "neg")}</span>` : ""}`;
    return [
      name,
      `<span class="tabular-nums">${c.cur === "COP" ? num(c.spend) + " COP" : usd(c.spend)}</span>`,
      `<span class="tabular-nums">${num(c.leads)}</span>`,
      `<span class="tabular-nums">${usd(c.cpl_real)}</span>`,
      `<span class="tabular-nums">${num(c.ganadas)}</span>`,
      `<span class="tabular-nums">${num(c.planes)}</span>`,
      `<span class="tabular-nums">${usd(c.valor_contrato)}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${TONE.pos}">${usd(c.cash)}</span>`,
      `<span class="tabular-nums">${usd(c.cac_real)}</span>`,
      `<span class="tabular-nums" style="color:${c.roas_real == null ? TONE.muted : c.roas_real >= 2.5 ? TONE.pos : TONE.neg}">${xf(c.roas_real)}</span>`,
      `<span class="tabular-nums">${num(c.n_anuncios)}</span>`,
    ];
  });

  const maxCash = Math.max(0, ...angulos.map((a) => a.cash_estimado || 0));
  const anguloCards = angulos.slice(0, 8).map((a, i) => anguloCard(a, i, maxCash)).join("");

  const titCards = titulares.map((x, i) => titularCard(x, i, { project, metrica })).join("");
  const control = landings[0] && landings[0].h1
    ? `<div class="card card-pad" style="border-style:dashed">
        <div class="flex gap-1 flex-wrap mb-2">${badge("CONTROL · titular vigente", "neutral")}</div>
        <p class="text-base font-semibold leading-snug" style="color:var(--text-2)">${escape(landings[0].h1)}</p>
        <p class="text-xs mt-2" style="color:var(--text-3)">${escape(p.control_nota || "Es la línea base. Un testeo compara UN titular nuevo contra este; el siguiente testeo compara contra el que haya ganado.")}</p>
      </div>`
    : "";

  const estadoTesteo = testeosErr
    ? `<div class="alert alert-neutral text-sm">No pude leer el histórico de testeos: ${escape(testeosErr)}</div>`
    : enCurso.length
      ? `<div class="alert alert-neutral text-sm"><b>Hay un testeo de titular en curso</b> — ${enCurso.map((x) => `<code>${escape(x.id)}</code> «${escape(x.variable)}» (${escape(x.metrica || "—")} inicial ${num(x.valor_inicial)}, abierto ${escape(x.abierto)} por ${escape(x.abierto_por)})`).join("; ")}. Un testeo por step: cerrarlo antes de abrir otro.</div>`
      : `<div class="alert alert-neutral text-sm">Ningún testeo de titular en curso en ${escape(project)}${cerrados.length ? ` · ${cerrados.length} cerrado${cerrados.length === 1 ? "" : "s"} en el histórico` : ""}.</div>`;

  const histRows = cerrados.map((x) => [
    `<code>${escape(x.id)}</code>`, escape(x.variable || ""), escape(x.metrica || "—"),
    `<span class="tabular-nums">${num(x.valor_inicial)} → ${num(x.valor_final)} (Δ ${num(x.delta)})</span>`,
    escape(x.resultado || "—"), escape(x.abierto_por || ""), escape(x.decision || ""),
  ]);

  // OJO: `id="pane"` NO es decorativo — ver la nota en pages/lead-score.js.
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
  <div class="max-w-7xl mx-auto">
  <div class="flex items-baseline gap-3 flex-wrap">
    <h1 class="text-xl font-bold" style="color:var(--text-1)">Ángulos ganadores → titulares</h1>
    <span class="text-sm" style="color:var(--text-3)">${escape(project)} · ${escape(m.desde || "")} → ${escape(m.hasta || "")} · generado ${escape(m.generado || "—")}</span>
  </div>
  <p class="text-sm mt-1" style="color:var(--text-2)">El titular de la página del VSL le habla al ángulo que ya compró el clic. Arriba, qué está vendiendo (campañas por caja, familias de copy); al lado, qué titular recibe ese clic hoy; abajo, los titulares propuestos para testear — uno por testeo, métrica <code>${escape(metrica)}</code>.</p>

  <div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">${kpis}</div>

  ${section("La landing y su titular HOY", "leído en vivo al generar — si el equipo lo cambia, aquí cambia")}
  <div class="grid gap-4" style="grid-template-columns:repeat(auto-fit,minmax(24rem,1fr))">
    ${landings.length ? landings.map((l) => landingCard(l, m.generado)).join("") : `<p class="text-sm italic" style="color:var(--text-3)">Ningún anuncio de la ventana trae enlace en la caché — corre bash/ads/creativos_sync.sh.</p>`}
  </div>

  ${section("Campañas por caja", "atribución por utm_campaign (CRM) → plan del mismo contacto ≤60 d → cuotas pagadas · caja real, no pixel")}
  ${tbl(["campaña", "pauta", "leads", "CPL", "won", "planes", "contrato", "caja", "CAC", "ROAS real", "ads"], campRows)}
  <p class="text-xs mt-1" style="color:var(--text-3)">«sin UTM» = leads cuyo contacto no trae utm_campaign: orgánico, directo o pauta sin etiquetar — su caja NO se puede repartir entre campañas. ${escape(m.regla_atribucion || "")}</p>

  ${section("Ángulos — familias de copy del anuncio", "agrupadas por el texto del anuncio; el video/hook cambia dentro de cada familia (nombre del anuncio)")}
  <div class="grid gap-4" style="grid-template-columns:repeat(auto-fill,minmax(20rem,1fr))">${anguloCards || `<p class="text-sm italic" style="color:var(--text-3)">Sin copy en caché.</p>`}</div>
  <p class="text-xs mt-2" style="color:var(--text-3)">${escape(m.regla_estimado || "")} · hook = vistas 25 %/plays · hold = 75 %/25 % (Meta).</p>

  ${section("Titulares propuestos", "params del spec — copy curado; se cambia re-publicando. Un titular por testeo, un testeo por step.")}
  ${estadoTesteo}
  <div class="grid gap-4 mt-3" style="grid-template-columns:repeat(auto-fill,minmax(22rem,1fr))">
    ${control}${titCards || `<p class="text-sm italic" style="color:var(--text-3)">El spec no trae <code>params.titulares</code> todavía.</p>`}
  </div>
  ${p.titulares_nota ? `<p class="text-xs mt-3" style="color:var(--text-2)">${escape(p.titulares_nota)}</p>` : ""}

  ${histRows.length ? section("Testeos de titular cerrados", "histórico compartido (Postgres ikigaigm.testeos)") + tbl(["id", "variable", "métrica", "inicial → final", "resultado", "por", "decisión"], histRows) : ""}

  <p class="mt-10 text-xs" style="color:var(--text-3)">
    Fuente: <code>bash/ads/angulos.sh --project "${escape(project)}"</code> (Postgres + caché de creativos + landings en vivo) · testeos: <code>bash/testeos/testeos.sh --step titular</code>.
    ${escape(m.fuente_copy || "")}
  </p>
  </div>
  </section>`;
}

module.exports = {
  id: "angulos",
  // `titulares`/`metrica`/`titulares_nota`/`control_nota` son presentación pura
  // (copy curado y rótulos) — overridable por lo mismo que `metas` en embudo:
  // inofensivos y necesarios para que el spec que los declara valide limpio.
  // Jamás llegan al shell (no son args de la fuente).
  manifest: { consumes: "object", overridable: ["project", "from", "to", "min_spend", "titulares", "metrica", "titulares_nota", "control_nota"] },
  render: renderAngulos,
};
