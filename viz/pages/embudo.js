// embudo page — EL CRUCE del embudo completo de un proyecto, desde el único
// objeto que emite bash/metrics/embudo.sh: pauta (Meta) → VSL (VTurb) →
// leads (CRM) → llamadas → ventas/cash (caja) → cuotas.
//
// Nació de la alineación DG 2026-08-19 (meeting b3f06835): el dashboard del
// embudo no cuadraba porque cada peldaño venía de una fuente distinta. La
// regla de esta página es que CADA número declara su fuente al lado, los
// cruces entre fuentes viven en su propia sección (conciliación) con el delta
// calculado, y los tramos sin instrumentar se muestran como huecos — un
// embudo que esconde de dónde sale cada peldaño es exactamente el bug que
// esta UI vino a matar.
//
// Las metas (ROAS ≥3.5 para escalar, etc.) son params del SPEC, no código:
// cuando el equipo fije la meta de leads que quedó pendiente, se agrega
// re-publicando el spec.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");
const { chartEl } = require("../blocks/charts");

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

function srcBadge(s) {
  return `<span class="badge badge-neutral" style="font-size:.65rem">${escape(s)}</span>`;
}

function tbl(headers, rows, { empty = "Sin datos." } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows.map((cells) => `<tr>${cells.map((c) => `<td class="align-top">${c}</td>`).join("")}</tr>`).join("");
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`;
}

// Meta vs valor: dirección declarada por métrica (subir es bueno / bajar es
// bueno). Solo colorea si la meta existe en los params del spec.
const META_DIR = { roas_real: "up", cash_total: "up", leads: "up", cpl_real: "down", cac_real: "down" };
function metaTone(key, value, metas) {
  const m = metas && metas[key];
  if (m == null || value == null) return null;
  const ok = META_DIR[key] === "down" ? Number(value) <= Number(m) : Number(value) >= Number(m);
  return ok ? "pos" : "neg";
}

// --- Salud del embudo vs benchmarks (params.metas.salud) ---
// Cada fila del spec trae una `ruta` punteada dentro del objeto de embudo.sh,
// con la MISMA semántica que `testeo_abrir.sh --metrica` (`pauta.0.ctr`,
// `vsl.total.tasa_play`): un número entero indexa listas. Además admite un
// cociente `a / b` (dos rutas) con `escala` (p.ej. 100 → %), para las tasas de
// paso que el script no emite ya calculadas. Umbrales `bueno`/`excelente`,
// dirección `dir` (max por defecto, min para costos). Son REFERENCIAS del
// spec, no metas de la org — por eso viven en params y se cambian
// re-publicando, y por eso la tabla imprime la referencia al lado del valor.
function resolvePath(path, obj) {
  if (!path) return null;
  let cur = obj;
  for (const part of String(path).trim().split(".")) {
    if (Array.isArray(cur)) {
      const i = Number(part);
      if (!Number.isInteger(i) || i < 0 || i >= cur.length) return null;
      cur = cur[i];
    } else if (cur && typeof cur === "object") {
      cur = cur[part];
    } else return null;
  }
  return typeof cur === "number" && Number.isFinite(cur) ? cur : null;
}
function resolveRuta(ruta, obj, escala) {
  const parts = String(ruta || "").split("/");
  if (parts.length > 2) return null;
  const a = resolvePath(parts[0], obj);
  if (a == null) return null;
  let v = a;
  if (parts.length === 2) {
    const b = resolvePath(parts[1], obj);
    if (b == null || b === 0) return null;
    v = a / b;
  }
  v = v * (Number(escala) || 1);
  return Math.round(v * 100) / 100;
}
function saludEstado(v, row) {
  if (v == null) return "sin dato";
  const min = row.dir === "min";
  const ok = (t) => (min ? v <= Number(t) : v >= Number(t));
  if (row.excelente != null && ok(row.excelente)) return "excelente";
  if (row.bueno != null && ok(row.bueno)) return "bueno";
  return "mejorable";
}
const SALUD_BADGE = { excelente: "badge-pos", bueno: "badge-brand", mejorable: "badge-cau", "sin dato": "badge-neutral" };
function fmtUnidad(v, u) {
  if (v == null) return "—";
  if (u === "%") return pctf(v);
  if (u === "$") return usd(v);
  if (u === "x") return `${Number(v).toLocaleString("es-CO")}x`;
  return num(v);
}
function saludRows(salud, d) {
  return (salud || []).map((row) => {
    const v = resolveRuta(row.ruta, d, row.escala);
    const estado = saludEstado(v, row);
    const cmp = row.dir === "min" ? "≤" : "≥";
    const ref = [
      row.bueno != null ? `${cmp}${fmtUnidad(row.bueno, row.unidad)} bueno` : "",
      row.excelente != null ? `${cmp}${fmtUnidad(row.excelente, row.unidad)} excelente` : "",
    ]
      .filter(Boolean)
      .join(" · ");
    return {
      estado,
      cells: [
        `<span class="font-semibold">${escape(String(row.metrica || row.ruta))}</span><br><code class="text-xs" style="color:var(--text-3)">${escape(String(row.ruta || ""))}</code>`,
        `<span class="tabular-nums font-semibold" style="color:var(--text-1)">${fmtUnidad(v, row.unidad)}</span>`,
        `<span class="text-xs tabular-nums" style="color:var(--text-3)">${escape(ref || "—")}</span>`,
        `<span class="badge ${SALUD_BADGE[estado]}">${escape(estado)}</span>`,
        row.fuente ? srcBadge(row.fuente) : "",
        `<span class="text-xs" style="color:var(--text-3)">${escape(String(row.nota || ""))}</span>`,
      ],
    };
  });
}

// Fila del embudo unificado: peldaño, valor, fuente, % del paso anterior.
function funnelRows(steps) {
  let prev = null;
  return steps
    .filter((s) => s.valor != null)
    .map((s) => {
      const pct = prev ? Math.round((1000 * s.valor) / prev) / 10 : null;
      prev = s.valor || prev;
      const w = pct == null ? 100 : Math.max(1, Math.min(100, pct));
      return [
        `<span class="font-semibold">${escape(s.nombre)}</span>`,
        `<span class="tabular-nums font-semibold" style="color:var(--text-1)">${num(s.valor)}</span>`,
        srcBadge(s.fuente),
        pct == null
          ? `<span style="color:var(--text-3)">—</span>`
          : `<div class="flex items-center gap-2"><span class="tabular-nums" style="min-width:3.2rem;color:${pct >= 100 ? TONE.cau : TONE.brand}">${pctf(pct)}</span>
             <span style="display:block;height:6px;border-radius:3px;width:${w}%;min-width:2px;background:var(--brand-solid);opacity:.6"></span></div>`,
        `<span class="text-xs" style="color:var(--text-3)">${escape(s.nota || "")}</span>`,
      ];
    });
}

function renderEmbudo(ui) {
  const p = ui.params || {};
  const metas = p.metas || {};
  const { rows } = fetchSource(ui.source || "embudo", p);
  const d = rows[0] || {};
  const m = d.meta || {};
  const k = d.kpis || {};
  const crm = d.crm || {};
  const vsl = d.vsl || {};
  const vslT = vsl.total || {};
  const ventas = d.ventas || {};
  const fres = d.frescura || {};
  const pautaUsd = (d.pauta || []).find((r) => r.cur === "USD") || (d.pauta || [])[0] || {};
  const pautaCop = (d.pauta || []).find((r) => r.cur === "COP");
  const serieCuotas = (d.cuotas || {}).serie || [];
  const series = d.series || [];

  // --- frescura: badges + alertas arriba, antes de cualquier número ---
  const fresBadges = [
    ["Meta", fres.ads_ultimo_dato, fres.ads_lag_dias],
    ["CRM (ingesta)", fres.crm_ultima_ingesta, fres.crm_ingesta_lag_dias],
    ["Caja", fres.ultimo_pago, null],
    ["VTurb", fres.vturb, null],
  ]
    .map(([lbl, val, lag]) => {
      const warn = lag != null && lag > 3;
      return `<span class="badge ${warn ? "badge-warn" : "badge-neutral"}" title="último dato de la fuente">${escape(lbl)}: ${escape(String(val ?? "—"))}${lag != null && lag > 0 ? ` (−${lag}d)` : ""}</span>`;
    })
    .join(" ");
  const alertas = (fres.alertas || [])
    .map((a) => `<div class="alert mt-2" style="border-left:3px solid var(--neg-solid)"><p class="text-sm">${escape(a)}</p></div>`)
    .join("");

  // --- KPIs de la ventana, contra metas si el spec las trae ---
  const cab = `
    ${kpi("Pauta (USD)", usd(k.spend_usd), { sub: pautaCop ? `+ ${num(pautaCop.spend)} COP aparte` : "solo USD entra a los ratios", title: m.regla_monedas || "" })}
    ${kpi("Leads (CRM)", num(k.leads), { tone: metaTone("leads", k.leads, metas) || "brand", sub: `${num(crm.pagados)} por pauta (${num(crm.con_anuncio)} con anuncio) · ${num(crm.organicos)} sin atribución`, title: (m.regla_leads || "") + (m.regla_atribucion ? " · " + m.regla_atribucion : "") })}
    ${kpi("CPL real", usd(k.cpl_real), { tone: metaTone("cpl_real", k.cpl_real, metas) || "brand", sub: "pauta USD / leads CRM" })}
    ${kpi("Planes iniciados", num(k.planes_iniciados), { sub: `${num(ventas.primeras_cuotas)} primeras cuotas cobradas` })}
    ${kpi("CAC real", usd(k.cac_real), { tone: metaTone("cac_real", k.cac_real, metas) || "brand", sub: "pauta USD / planes iniciados" })}
    ${kpi("Cash cobrado", usd(k.cash_total), { tone: "pos", sub: `${usd(ventas.cash_nuevas)} nuevas + ${usd(ventas.cash_cuotas)} cuotas` })}
    ${kpi("ROAS real", k.roas_real ?? "—", { tone: metaTone("roas_real", k.roas_real, metas) || "brand", sub: `pixel dice ${k.roas_pixel ?? "—"}${metas.roas_real ? ` · meta ≥${metas.roas_real}` : ""}`, title: "cash cobrado / pauta USD — la verdad del dinero, no el pixel" })}`;

  // --- el embudo unificado, cada peldaño con su fuente ---
  const fEmbudo = funnelRows([
    { nombre: "Impresiones", valor: pautaUsd.impresiones, fuente: "Meta", nota: "" },
    { nombre: "Clics", valor: pautaUsd.clics, fuente: "Meta", nota: `CTR ${pctf(pautaUsd.ctr)} · CPC ${usd(pautaUsd.cpc)}` },
    { nombre: "Aterrizajes (LPV)", valor: pautaUsd.aterrizajes, fuente: "Meta", nota: "" },
    { nombre: "Player visto", valor: vslT.impresiones, fuente: "VTurb", nota: "incluye tráfico no pagado (orgánico/remarketing)" },
    { nombre: "Plays", valor: vslT.plays, fuente: "VTurb", nota: `tasa de play ${pctf(vslT.tasa_play)}` },
    { nombre: "Pasaron el pitch", valor: vslT.pasaron_pitch, fuente: "VTurb", nota: "" },
    { nombre: "Clic al CTA", valor: vslT.cta_clicks, fuente: "VTurb", nota: "" },
    { nombre: "Leads", valor: crm.leads, fuente: "CRM", nota: "aquí vive la fuga de la pregunta del capital" },
    { nombre: "Llamadas", valor: (crm.llamadas || {}).total, fuente: "meetings", nota: `${num((crm.llamadas || {}).con_transcript)} con transcript · ${num((crm.llamadas || {}).analizadas)} analizadas` },
    { nombre: "Ganadas (CRM)", valor: crm.ganadas, fuente: "CRM", nota: "" },
    { nombre: "Planes iniciados", valor: ventas.planes_iniciados, fuente: "caja", nota: `${usd(ventas.valor_contrato)} en contratos${(ventas.excluidos || {}).planes_cancelados ? ` · ${num(ventas.excluidos.planes_cancelados)} cancelados excluidos` : ""}` },
  ]);

  // --- salud vs benchmarks: cada tasa de paso contra la referencia del spec ---
  const saludList = Array.isArray(metas.salud) ? metas.salud : [];
  const saludR = saludRows(saludList, d);
  const saludCount = saludR.reduce((acc, r) => ((acc[r.estado] = (acc[r.estado] || 0) + 1), acc), {});
  const saludResumen = ["excelente", "bueno", "mejorable", "sin dato"]
    .filter((e) => saludCount[e])
    .map((e) => `<span class="badge ${SALUD_BADGE[e]}">${saludCount[e]} ${escape(e)}</span>`)
    .join(" ");
  const tSalud = saludList.length
    ? tbl(["Métrica", "Tu valor", "Referencia", "Estado", "Fuente", "Nota"], saludR.map((r) => r.cells))
    : `<div class="alert"><p class="text-sm">Sin benchmarks configurados: agrega <code>params.metas.salud</code> al spec (lista de <code>{metrica, ruta, bueno, excelente, dir, unidad}</code>).</p></div>`;

  // --- el último eslabón, explicado: de qué cohorte viene cada plan ---
  const orig = ventas.planes_por_origen || {};
  const exc = ventas.excluidos || {};
  const origenCards = [
    ["Won · lead de la ventana", orig.won_lead_ventana, "pos", "la cohorte comparable con las ganadas del CRM"],
    ["Won · lead previo (rezagados)", orig.won_lead_previo, "brand", "leads de meses anteriores que compraron ahora"],
    ["Opp aún abierta", orig.opp_abierta, "cau", "pagaron y el CRM no los movió a venta — higiene"],
    ["Sin opp en el CRM", orig.sin_opp, "cau", "venta sin rastro en el CRM"],
    ["Cancelados (excluidos)", exc.planes_cancelados, "muted", `${usd(exc.valor_contrato)} de contrato que no cuenta${Number(ventas.cash_en_cancelados) > 0 ? ` · ${usd(ventas.cash_en_cancelados)} cobrados ahí` : ""}`],
  ]
    .map(([l, v, t, s]) => kpi(l, num(v), { tone: t, sub: s }))
    .join("");

  // --- VSL por video: la mesa del testeo de hooks ---
  const tVsl = vsl.error
    ? `<div class="alert" style="border-left:3px solid var(--neg-solid)"><p class="text-sm"><strong>VTurb no respondió:</strong> ${escape(String(vsl.error))}</p></div>`
    : tbl(
        ["Video", "Impr.", "Plays", "Play %", "Ret 25/50/75", "Pitch %", "CTA", "Engagement"],
        (vsl.videos || [])
          .filter((v) => (v.plays_unicos || 0) > 0)
          .map((v) => [
            `<span class="font-semibold">${escape(String(v.titulo || v.video_id))}</span>`,
            `<span class="tabular-nums">${num(v.impresiones_unicas)}</span>`,
            `<span class="tabular-nums">${num(v.plays_unicos)}</span>`,
            `<span class="tabular-nums font-semibold">${pctf(v.tasa_play)}</span>`,
            `<span class="tabular-nums text-xs">${pctf(v.ret_25)} · ${pctf(v.ret_50)} · ${pctf(v.ret_75)}</span>`,
            `<span class="tabular-nums">${pctf(v.tasa_pitch)}</span>`,
            `<span class="tabular-nums">${num(v.cta_clicks)}</span>`,
            `<span class="tabular-nums">${pctf(v.engagement_rate)}</span>`,
          ]),
        { empty: "Sin videos con plays en la ventana." }
      );

  // --- atribución por campaña: los ángulos ganadores ---
  const tAtr = tbl(
    ["Campaña", "Leads", "GHL · solo form · con ad", "Spend", "CPL real", "Ganadas", "Planes", "Contrato", "Cash"],
    (d.atribucion || []).map((r) => [
      `<span class="font-semibold">${escape(String(r.campana))}</span>`,
      `<span class="tabular-nums">${num(r.leads)}</span>`,
      `<span class="tabular-nums text-xs" style="color:var(--text-3)" title="leads con campaña por la atribución nativa de GHL · leads que solo la traen por el utm_campaign del formulario · leads con anuncio (attr_ad_id)">${num(r.leads_ghl)} · ${num(r.leads_solo_form)} · ${num(r.leads_con_anuncio)}</span>`,
      `<span class="tabular-nums">${r.spend == null ? "—" : usd(r.spend)}</span>`,
      `<span class="tabular-nums">${r.cpl_real == null ? "—" : usd(r.cpl_real)}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${(r.ganadas || 0) > 0 ? TONE.pos : TONE.muted}">${num(r.ganadas)}</span>`,
      `<span class="tabular-nums">${num(r.planes)}</span>`,
      `<span class="tabular-nums">${usd(r.valor_contrato)}</span>`,
      `<span class="tabular-nums font-semibold">${usd(r.cash)}</span>`,
    ])
  );

  // --- conciliación entre fuentes ---
  const tConc = tbl(
    ["Handoff", "A", "B", "Traspaso", "Lectura"],
    (d.conciliacion || []).map((c) => [
      `<span class="font-semibold">${escape(String(c.handoff))}</span>`,
      `<span class="text-xs">${escape(String(c.a))}<br><span class="tabular-nums font-semibold text-sm">${num(c.valor_a)}</span></span>`,
      `<span class="text-xs">${escape(String(c.b))}<br><span class="tabular-nums font-semibold text-sm">${num(c.valor_b)}</span></span>`,
      `<span class="tabular-nums font-semibold" style="color:${c.pct_traspaso == null ? TONE.muted : c.pct_traspaso > 100 ? TONE.cau : TONE.brand}">${pctf(c.pct_traspaso)}</span>`,
      `<span class="text-xs" style="color:var(--text-3)">${escape(String(c.nota || ""))}</span>`,
    ])
  );

  // --- cuotas: el frente crítico. Chart multi-serie + tabla twin ---
  const cuotasSpec = serieCuotas.length
    ? {
        kind: "line",
        labels: serieCuotas.map((r) => r.mes),
        series: [
          { label: "Cobrado/día (todo)", data: serieCuotas.map((r) => Number(r.prom_dia) || 0) },
          { label: "Cobrado/día (solo cuotas n≥2)", data: serieCuotas.map((r) => Number(r.prom_dia_cuotas) || 0) },
        ],
      }
    : null;
  const tCuotas = tbl(
    ["Mes", "Cobrado", "De cuotas", "Cuotas/día", "Planes debían", "Pagaron", "% pagando", "Empiezan", "Dejan"],
    serieCuotas.map((r) => [
      `<span class="tabular-nums font-semibold">${escape(String(r.mes))}</span>`,
      `<span class="tabular-nums">${usd(r.cobrado)}</span>`,
      `<span class="tabular-nums">${usd(r.cobrado_cuotas)}</span>`,
      `<span class="tabular-nums font-semibold">${usd(r.prom_dia_cuotas)}</span>`,
      `<span class="tabular-nums">${num(r.planes_debian)}</span>`,
      `<span class="tabular-nums">${num(r.planes_pagaron)}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${(r.pct_pagando || 0) >= 70 ? TONE.pos : (r.pct_pagando || 0) >= 50 ? TONE.cau : TONE.neg}">${pctf(r.pct_pagando)}</span>`,
      `<span class="tabular-nums" style="color:${TONE.pos}">${num(r.empiezan)}</span>`,
      `<span class="tabular-nums" style="color:${TONE.neg}">${num(r.dejan)}</span>`,
    ])
  );

  // --- serie mensual del embudo (benchmarks) ---
  // Cash vs pauta comparten unidad (USD): la brecha entre las dos líneas ES el
  // ROAS real visto. Leads/CAC/ROAS viven en otras escalas — van en la tabla
  // gemela y, el ROAS, en su propio gráfico contra la meta del spec.
  const serieSpec = series.length
    ? {
        kind: "line",
        labels: series.map((r) => r.mes),
        series: [
          { label: "Cash cobrado (USD)", data: series.map((r) => Number(r.cash) || 0) },
          { label: "Pauta (USD)", data: series.map((r) => Number(r.spend_usd) || 0) },
        ],
      }
    : null;
  const roasSpec = series.length
    ? {
        kind: "line",
        labels: series.map((r) => r.mes),
        series: [
          { label: "ROAS real", data: series.map((r) => Number(r.roas_real) || 0) },
          ...(metas.roas_real ? [{ label: `Meta (${metas.roas_real})`, data: series.map(() => Number(metas.roas_real)) }] : []),
        ],
      }
    : null;
  const tRoas = tbl(
    ["Mes", "ROAS real", "CAC real", "Meta ROAS"],
    series.map((r) => [
      `<span class="tabular-nums font-semibold">${escape(String(r.mes))}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${metas.roas_real && r.roas_real != null ? (Number(r.roas_real) >= Number(metas.roas_real) ? TONE.pos : TONE.neg) : TONE.brand}">${r.roas_real ?? "—"}</span>`,
      `<span class="tabular-nums">${usd(r.cac_real)}</span>`,
      `<span class="tabular-nums" style="color:var(--text-3)">${metas.roas_real ?? "—"}</span>`,
    ])
  );
  const tSerie = tbl(
    ["Mes", "Pauta USD", "Leads", "Planes", "Cash", "CAC real", "ROAS real"],
    series.map((r) => [
      `<span class="tabular-nums font-semibold">${escape(String(r.mes))}</span>`,
      `<span class="tabular-nums">${usd(r.spend_usd)}</span>`,
      `<span class="tabular-nums">${num(r.leads)}</span>`,
      `<span class="tabular-nums">${num(r.planes)}</span>`,
      `<span class="tabular-nums">${usd(r.cash)}</span>`,
      `<span class="tabular-nums">${usd(r.cac_real)}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${metas.roas_real && r.roas_real != null ? (Number(r.roas_real) >= Number(metas.roas_real) ? TONE.pos : TONE.neg) : TONE.brand}">${r.roas_real ?? "—"}</span>`,
    ])
  );

  const sinInstr = (d.sin_instrumentar || [])
    .map(
      (h) => `<div class="card card-pad">
        <p class="text-xs uppercase tracking-wider" style="color:var(--text-3)">${escape(String(h.tramo))}</p>
        <p class="text-sm mt-1" style="color:var(--text-2)">${escape(String(h.estado))}</p>
      </div>`
    )
    .join("");

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

  // OJO: `id="pane"` NO es decorativo — ver la nota en pages/lead-score.js.
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
  <div class="max-w-6xl mx-auto">
    <div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">Embudo — el cruce</h1>
      <span class="badge badge-neutral">${escape(String(m.proyecto || "—"))}</span>
      <span class="badge badge-neutral">${escape(String(m.desde || "—"))} → ${escape(String(m.hasta || "—"))}</span>
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs" style="color:var(--text-brand)">abrir solo ↗</a>
    </div>
    <p class="mt-1 text-sm" style="color:var(--text-3)">
      Cada peldaño declara su fuente. Los leads salen del CRM, no de ningún Excel;
      la verdad del dinero es la caja (installments), no el pixel.
    </p>

    <div class="flex flex-wrap gap-2 mt-3">${fresBadges}</div>
    ${alertas}

    <div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(10rem,1fr))">${cab}</div>

    ${section("El embudo, fuente por fuente", "el % es traspaso contra el peldaño anterior; >100% = entra tráfico que el peldaño anterior no ve")}
    ${tbl(["Peldaño", "Valor", "Fuente", "Traspaso", "Nota"], fEmbudo)}

    ${section("Salud del embudo vs benchmarks", "cada tasa de paso contra una referencia declarada en el spec — el estado dice dónde está el cuello, no la meta de la org")}
    ${saludResumen ? `<div class="flex flex-wrap gap-2 mb-3">${saludResumen}</div>` : ""}
    ${tSalud}
    ${metas.salud_nota ? `<p class="mt-2 text-xs" style="color:var(--text-3)">${escape(String(metas.salud_nota))}</p>` : ""}

    ${section("Conciliación entre fuentes", "los handoffs donde las fuentes se tocan — aquí es donde un dashboard miente sin que se note")}
    ${tConc}

    ${section("Planes iniciados, por origen", "el último eslabón explicado: la diferencia entre ganadas del CRM y planes no es discrepancia, es cohorte")}
    <div class="grid gap-3" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">${origenCards}</div>

    ${section("VSL por video", "la mesa del testeo de hooks: cada video nuevo aparece como fila con sus tasas — VTurb en vivo")}
    ${tVsl}

    ${section("Atribución por campaña", "los ángulos ganadores: qué campaña trae leads que COMPRAN, no solo leads — cash con guardia temporal de +60 días")}
    ${tAtr}
    <p class="mt-2 text-xs" style="color:var(--text-3)">
      La fila «sin atribución» son leads sin UTM (orgánico, directo, o tracking roto). No se reparte
      entre campañas: si es grande, el problema es de instrumentación, y eso también es un dato.
    </p>

    ${section("Cuotas — el frente crítico", "la medición mensual acordada el 19-ago: cuánto entra por día, % de planes pagando, quiénes empiezan y quiénes dejan")}
    ${chartCard(cuotasSpec, "showcuotas", tCuotas)}
    <p class="mt-2 text-xs" style="color:var(--text-3)">
      «Dejan» = planes con cuota vencida ese mes sin pagar que SÍ habían pagado antes — el cliente que
      venía pagando y paró. El detalle por número de cuota y cohorte vive en la UI
      «Impago y deserción de cuotas» (la curva completa).
    </p>

    ${section("Serie mensual del embudo", "los benchmarks: cash vs pauta (la brecha es el ROAS real visto) y el ROAS contra su meta")}
    <div class="grid gap-4" style="grid-template-columns:repeat(auto-fit,minmax(22rem,1fr))">
      ${chartCard(serieSpec, "showserie", tSerie)}
      ${chartCard(roasSpec, "showroas", tRoas)}
    </div>

    ${section("Sin instrumentar", "los tramos que este cruce todavía no ve — declarados, no inventados")}
    <div class="grid gap-4" style="grid-template-columns:repeat(auto-fit,minmax(18rem,1fr))">${sinInstr}</div>

    <p class="mt-10 text-xs" style="color:var(--text-3)">
      Fuente: <code>bash/metrics/embudo.sh --project "${escape(String(m.proyecto || ""))}"</code> ·
      generado ${escape(String(m.generado || "—"))} · VTurb en vivo, resto Postgres.
      Las metas son params del spec (<code>params.metas</code>), editables re-publicando.
    </p>
  </div>
  </section>`;
}

module.exports = {
  id: "embudo",
  // `metas` es presentación pura (umbrales que colorean KPIs) — overridable
  // por lo mismo que x/y/kind en chart.js: inofensivo y necesario para que la
  // spec que lo declara valide limpia. Jamás llega al shell (no es arg).
  manifest: { consumes: "object", overridable: ["project", "from", "to", "meses", "metas"] },
  render: renderEmbudo,
};
