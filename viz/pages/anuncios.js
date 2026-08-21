// anuncios page — el CREATIVO como unidad: una tarjeta por anuncio con su
// miniatura, spend, leads/ventas/caja REAL del CRM, compras y ROAS del pixel,
// CTR, hook/hold, y la tabla gemela. Hueco #2 del contraste con el dashboard comercial (2026-08-21): el
// equipo analiza anuncios en la «plataforma de Bala» (tarjetas con el
// creativo + Revenue·Last/ROAS) y el Cerebro solo tenía ad_stats --by ad sin
// imagen, sin tipo (marca vs adquisición) y sin hook/hold.
//
// Dos atribuciones lado a lado, siempre etiquetadas: ROAS REAL = cash cobrado
// de los leads del CRM atribuidos al ad (crm_contacts.attr_ad_id, desde
// 2026-08-21) / inversión; ROAS PIXEL = lo que Meta atribuye. El KPI de
// cobertura dice qué fracción de los leads del mes trae anuncio — sin eso el
// ROAS real se lee como si fuera exhaustivo. La miniatura viene de la caché
// local que llena creativos_sync.sh; si falta, placeholder + aviso, nunca una
// llamada a Meta desde el render.
//
// `tipo` es arg de la fuente (re-render por @get); `orden` es presentación
// pura (se aplica en JS sobre las filas ya traídas). Un solo fetch por render.

const { fetchSource } = require("../lib/datasources");
const { escape, selectCtl } = require("../lib/kit");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };
const TIPO_OPTS = [["adquisicion", "Adquisición (llevan tráfico a la landing)"], ["marca", "Marca (seguidores y video)"], ["todos", "Todos"]];
const ORDEN_OPTS = [["spend", "Más inversión"], ["roas_real", "Mejor ROAS real"], ["cash", "Más caja"], ["leads", "Más leads"], ["roas", "Mejor ROAS pixel"], ["compras", "Más compras pixel"], ["hook", "Mejor hook"], ["ctr", "Mejor CTR"], ["cpa", "Menor CPA pixel"]];

function num(v) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  return Number.isNaN(n) ? escape(String(v)) : n.toLocaleString("es-CO");
}
function money(v, cur) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  if (Number.isNaN(n)) return escape(String(v));
  return (cur === "COP" ? "COP " : "$") + Math.round(n).toLocaleString("es-CO");
}
function pct(v) { return v == null ? "—" : `${Number(v).toLocaleString("es-CO")}%`; }
function mult(v) { return v == null ? "—" : `${Number(v).toLocaleString("es-CO")}x`; }
function roasTone(r) { if (r == null) return TONE.muted; const n = Number(r); return n >= 3 ? TONE.pos : n >= 1 ? TONE.brand : TONE.neg; }

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
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`;
}

function thumb(r) {
  if (r.miniatura) {
    return `<img src="${escape(r.miniatura)}" alt="" loading="lazy" referrerpolicy="no-referrer"
      style="width:100%;aspect-ratio:4/5;object-fit:cover;border-radius:var(--r-md,8px);background:var(--surface-2)">`;
  }
  const ini = String(r.anuncio || "?").replace(/[^A-Za-z0-9]+/g, " ").trim().split(" ").slice(0, 2).map((w) => w[0]).join("").toUpperCase() || "?";
  return `<div style="width:100%;aspect-ratio:4/5;border-radius:var(--r-md,8px);background:var(--surface-2);display:flex;align-items:center;justify-content:center;color:var(--text-3);font-weight:700;font-size:1.4rem" title="sin miniatura en caché — corre bash/ads/creativos_sync.sh">${escape(ini)}</div>`;
}

function card(r, maxSpend) {
  const w = maxSpend > 0 ? Math.max(2, Math.round((100 * Number(r.spend || 0)) / maxSpend)) : 0;
  const estado = r.estado === "ACTIVE" ? `<span class="badge badge-pos" style="font-size:.6rem">activo</span>` : `<span class="badge badge-neutral" style="font-size:.6rem">${escape(String(r.estado || "—").toLowerCase())}</span>`;
  const stat = (l, v, color) => `<div><div class="text-xs" style="color:var(--text-3)">${escape(l)}</div><div class="tabular-nums text-sm font-semibold" style="color:${color || "var(--text-1)"}">${v}</div></div>`;
  return `<div class="card card-pad" style="display:flex;flex-direction:column;gap:.6rem">
    ${thumb(r)}
    <div>
      <div class="flex items-start gap-2">
        <span class="font-semibold text-sm" style="color:var(--text-1);line-height:1.2;min-width:0;overflow-wrap:anywhere" title="${escape(String(r.anuncio))}">${escape(String(r.anuncio).slice(0, 48))}</span>
        <span class="ml-auto" style="white-space:nowrap;flex:none">${estado}</span>
      </div>
      <div class="text-xs mt-0.5" style="color:var(--text-3)" title="${escape(String(r.campana))} · ${escape(String(r.adset))}">${escape(String(r.campana).slice(0, 40))}</div>
    </div>
    <div style="height:4px;border-radius:2px;background:var(--surface-2)"><div style="height:4px;border-radius:2px;width:${w}%;background:var(--brand-solid);opacity:.7"></div></div>
    <div class="grid gap-x-3 gap-y-2" style="grid-template-columns:repeat(3,1fr)">
      ${stat("Inversión", money(r.spend, r.cur))}
      ${stat("Leads (CRM)", num(r.leads))}
      ${stat("CPL real", money(r.cpl_real, r.cur))}
      ${stat("Ventas (planes)", `${num(r.planes)}${Number(r.won) ? `<span class="text-xs font-normal" style="color:var(--text-3)"> · ${num(r.won)} won</span>` : ""}`)}
      ${stat("Caja cobrada", money(r.cash, "USD"), Number(r.cash) > 0 ? TONE.pos : undefined)}
      ${stat("ROAS real", mult(r.roas_real), roasTone(r.roas_real))}
      ${stat("ROAS pixel", mult(r.roas_pixel), roasTone(r.roas_pixel))}
      ${stat("CTR link", pct(r.ctr_link))}
      ${stat("Hook (25%/plays)", pct(r.hook_pct))}
    </div>
  </div>`;
}

const SORTS = {
  spend: (a, b) => Number(b.spend || 0) - Number(a.spend || 0),
  roas: (a, b) => Number(b.roas_pixel || 0) - Number(a.roas_pixel || 0),
  roas_real: (a, b) => Number(b.roas_real || 0) - Number(a.roas_real || 0) || Number(b.cash || 0) - Number(a.cash || 0),
  cash: (a, b) => Number(b.cash || 0) - Number(a.cash || 0) || Number(b.contrato || 0) - Number(a.contrato || 0),
  leads: (a, b) => Number(b.leads || 0) - Number(a.leads || 0) || Number(b.spend || 0) - Number(a.spend || 0),
  compras: (a, b) => Number(b.compras || 0) - Number(a.compras || 0) || Number(b.spend || 0) - Number(a.spend || 0),
  hook: (a, b) => Number(b.hook_pct || 0) - Number(a.hook_pct || 0),
  ctr: (a, b) => Number(b.ctr_link || 0) - Number(a.ctr_link || 0),
  cpa: (a, b) => (a.cpa == null) - (b.cpa == null) || Number(a.cpa || 0) - Number(b.cpa || 0),
};

function renderAnuncios(ui) {
  const p = ui.params || {};
  const tipo = TIPO_OPTS.some(([v]) => v === p.tipo) ? p.tipo : "adquisicion";
  const orden = SORTS[p.orden] ? p.orden : "spend";
  let rows = [], err;
  try {
    ({ rows } = fetchSource(ui.source || "ad_anuncios", { ...p, tipo }));
  } catch (e) { err = e.message; }
  rows = (rows || []).slice().sort(SORTS[orden]);

  const curs = [...new Set(rows.map((r) => r.cur))];
  const cur = curs.length === 1 ? curs[0] : "";
  const sum = (k) => rows.reduce((a, r) => a + (Number(r[k]) || 0), 0);
  const spend = sum("spend"), impr = sum("impr"), clics = sum("clics_link"), compras = sum("compras"), valor = sum("valor_pixel"), vv = sum("vv"), vv25 = sum("vv25");
  const leads = sum("leads"), won = sum("won"), planes = sum("planes"), contrato = sum("contrato"), cash = sum("cash");
  const cob = rows[0] || {};
  const cobTotal = Number(cob.cob_leads_total || 0), cobConAd = Number(cob.cob_leads_con_ad || 0), cobEnVentana = Number(cob.cob_leads_ad_en_ventana || 0);
  const spendUsd = rows.filter((r) => r.cur === "USD").reduce((a, r) => a + (Number(r.spend) || 0), 0);
  const roasReal = spendUsd ? Math.round((100 * cash) / spendUsd) / 100 : null;
  const conMini = rows.filter((r) => r.miniatura).length;
  const maxSpend = rows.reduce((m, r) => Math.max(m, Number(r.spend) || 0), 0);

  const cab = `
    ${kpi("Inversión", curs.length > 1 ? "mixta" : money(spend, cur), { sub: `${num(rows.length)} anuncios con gasto · ${num(rows.filter((r) => r.estado === "ACTIVE").length)} activos`, title: curs.length > 1 ? "hay más de una moneda: no se suma" : "" })}
    ${kpi("Clics al link", num(clics), { sub: `${num(impr)} impr. · CTR ${impr ? (Math.round((10000 * clics) / impr) / 100).toLocaleString("es-CO") : "—"}% · CPM ${impr ? money((1000 * spend) / impr, cur) : "—"}` })}
    ${kpi("Leads atribuidos", `${num(leads)}<span class="text-sm" style="color:var(--text-3)">/${num(cobTotal)}</span>`, { tone: cobTotal && leads / cobTotal >= 0.6 ? "pos" : "cau", sub: cobTotal ? `de ${num(cobTotal)} leads del CRM en la ventana · ${num(cobConAd)} traen anuncio (${Math.round((100 * cobConAd) / cobTotal)}%)${cobConAd > cobEnVentana ? ` · ${num(cobConAd - cobEnVentana)} de un ad sin gasto en la ventana` : ""}` : "sin leads del CRM en la ventana", title: "lead = oportunidad del CRM creada en la ventana; anuncio = attr_ad_id del contacto (atribución de GHL, último toque). Los que no traen anuncio son orgánico/directo o clics sin UTM: no se reparten." })}
    ${kpi("Ventas (planes)", num(planes), { sub: `${num(won)} won en CRM · contrato ${money(contrato, "USD")} · CAC ${planes ? money(spendUsd / planes, "USD") : "—"}`, title: "primer payment_plan del contacto creado ≤60 días después del lead (misma guardia que embudo.sh)" })}
    ${kpi("Caja cobrada", money(cash, "USD"), { tone: cash > 0 ? "pos" : "brand", sub: `ROAS real ${roasReal == null ? "—" : mult(roasReal)} · cuotas pagadas de esos planes`, title: "cash = cuotas con payment_date de los planes atribuidos / inversión USD de la ventana" })}
    ${kpi("ROAS pixel", spend ? mult(Math.round((100 * valor) / spend) / 100) : "—", { tone: "brand", sub: `${num(compras)} compras · ${money(valor, cur)} atribuido por Meta`, title: "valor de compra del pixel / inversión — atribución de Meta, no caja; se muestra al lado del real para ver la brecha" })}
    ${kpi("Hook promedio", vv ? pct(Math.round((1000 * vv25) / vv) / 10) : "—", { sub: "vistas al 25% / plays", title: "video_views de Meta aquí es plays por autoplay (≈impresiones): el hook se mide con el primer cuartil" })}
    ${kpi("Miniaturas", `${num(conMini)}<span class="text-sm" style="color:var(--text-3)">/${num(rows.length)}</span>`, { tone: conMini === rows.length ? "pos" : "cau", sub: conMini < rows.length ? "faltan: bash/ads/creativos_sync.sh" : "caché local al día" })}`;

  const reget = `@get('/ui/${escape(ui.id)}?tipo='+$adsTipo+'&orden='+$adsOrden)`;
  const sig = `{adsTipo:'${escape(tipo)}',adsOrden:'${escape(orden)}',loadingads:false,showtabla:false}`;
  const controls = `<div class="flex flex-wrap items-center gap-2 mt-4" data-signals="${sig}">
    <span class="text-xs" style="color:var(--text-3)">Tipo</span>
    ${selectCtl("adsTipo", tipo, TIPO_OPTS, reget, "loadingads")}
    <span class="text-xs ml-2" style="color:var(--text-3)">Orden</span>
    ${selectCtl("adsOrden", orden, ORDEN_OPTS, reget, "loadingads")}
  </div>`;

  const grid = rows.length
    ? `<div class="grid gap-4" style="grid-template-columns:repeat(auto-fill,minmax(15rem,1fr))">${rows.map((r) => card(r, maxSpend)).join("")}</div>`
    : `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">Sin anuncios con gasto en la ventana.</p>`;

  const tabla = tbl(
    ["Anuncio", "Campaña", "Tipo", "Estado", "Inversión", "Leads", "CPL", "Ventas", "Contrato", "Caja", "ROAS real", "CAC", "Compras px", "ROAS px", "CPA px", "Impr.", "Clics link", "CTR", "CPM", "LPV", "Hook", "Hold", "Días"],
    rows.map((r) => [
      `<span class="font-semibold" title="${escape(String(r.ad_id))}">${escape(String(r.anuncio))}</span>`,
      `<span class="text-xs">${escape(String(r.campana))}</span>`,
      `<span class="badge badge-neutral" style="font-size:.6rem">${escape(String(r.tipo))}</span>`,
      `<span class="text-xs">${escape(String(r.estado || "—").toLowerCase())}</span>`,
      `<span class="tabular-nums font-semibold">${money(r.spend, r.cur)}</span>`,
      `<span class="tabular-nums font-semibold">${num(r.leads)}</span>`,
      `<span class="tabular-nums">${money(r.cpl_real, r.cur)}</span>`,
      `<span class="tabular-nums font-semibold">${num(r.planes)}${Number(r.won) ? `<span class="text-xs font-normal" style="color:var(--text-3)"> (${num(r.won)} won)</span>` : ""}</span>`,
      `<span class="tabular-nums">${money(r.contrato, "USD")}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${Number(r.cash) > 0 ? TONE.pos : "inherit"}">${money(r.cash, "USD")}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${roasTone(r.roas_real)}">${mult(r.roas_real)}</span>`,
      `<span class="tabular-nums">${money(r.cac, r.cur)}</span>`,
      `<span class="tabular-nums">${num(r.compras)}</span>`,
      `<span class="tabular-nums" style="color:${roasTone(r.roas_pixel)}">${mult(r.roas_pixel)}</span>`,
      `<span class="tabular-nums">${money(r.cpa, r.cur)}</span>`,
      `<span class="tabular-nums">${num(r.impr)}</span>`,
      `<span class="tabular-nums">${num(r.clics_link)}</span>`,
      `<span class="tabular-nums">${pct(r.ctr_link)}</span>`,
      `<span class="tabular-nums">${money(r.cpm, r.cur)}</span>`,
      `<span class="tabular-nums">${num(r.lpv)}</span>`,
      `<span class="tabular-nums">${pct(r.hook_pct)}</span>`,
      `<span class="tabular-nums">${pct(r.hold_pct)}</span>`,
      `<span class="text-xs tabular-nums" style="color:var(--text-3)">${escape(String(r.primer_dia || "").slice(5))} → ${escape(String(r.ultimo_dia || "").slice(5))}</span>`,
    ])
  );

  const body = err
    ? `<div class="alert mt-4" style="border-left:3px solid var(--neg-solid)"><p class="text-sm">${escape(err)}</p></div>`
    : `<div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(10rem,1fr))">${cab}</div>
       ${section("Anuncios", `${orden === "spend" ? "de mayor a menor inversión" : "ordenados por " + ORDEN_OPTS.find(([v]) => v === orden)[1].toLowerCase()} — la barra es la inversión relativa al anuncio que más gastó${["roas", "roas_real", "cpa", "cash"].includes(orden) ? " · ojo: con poca inversión el ROAS/CPA es ruido (una venta sobre $6 da 43x); mirá la barra antes que el número" : ""}`)}
       <div class="relative" data-signals="{showtabla:false}">
         <style>#ads-loading{opacity:0;transition:opacity .2s ease}#ads-loading.on{opacity:1}</style>
         <div id="ads-loading" data-class:on="$loadingads" class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center rounded-xl" style="background:color-mix(in srgb, var(--surface-1) 50%, transparent)">
           <div class="w-7 h-7 rounded-full border-2 animate-spin" style="border-color:var(--border-1);border-top-color:var(--brand-solid)"></div>
         </div>
         ${grid}
         <div class="mt-4 pt-2" style="border-top:1px solid var(--border-1)">
           <button data-on:click="$showtabla=!$showtabla" class="text-xs" style="color:var(--text-brand)">
             <span data-text="$showtabla ? 'ocultar tabla' : 'ver tabla'">ver tabla</span>
           </button>
           <div data-show="$showtabla" style="display:none" class="mt-2">${tabla}</div>
         </div>
       </div>`;

  // OJO: `id="pane"` NO es decorativo — ver la nota en pages/lead-score.js.
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
  <div class="max-w-7xl mx-auto">
    <div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">Anuncios</h1>
      <span class="badge badge-neutral">${escape(String(p.project || "—"))}</span>
      ${p.from || p.to ? `<span class="badge badge-neutral">${escape(String(p.from || "…"))} → ${escape(String(p.to || "hoy"))}</span>` : `<span class="badge badge-neutral">mes en curso</span>`}
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs" style="color:var(--text-brand)">abrir solo ↗</a>
    </div>
    <p class="mt-1 text-sm" style="color:var(--text-3)">
      El creativo como unidad, con <strong>dos atribuciones lado a lado</strong>: <strong>real</strong> = leads del CRM atribuidos al anuncio (atribución de GHL, último toque) → planes ≤60 d → caja cobrada;
      <strong>pixel</strong> = compras y valor que Meta se atribuye. «Leads atribuidos» dice qué fracción de los leads del mes trae anuncio — el resto es orgánico/directo y no se reparte. «Marca» = campañas de seguidores y video: objetivo de marca o clics que no llegan a la landing (van al perfil).
    </p>
    ${controls}
    ${body}
    <p class="mt-10 text-xs" style="color:var(--text-3)">
      Fuente: <code>bash/ads/anuncios.sh --project "${escape(String(p.project || ""))}" --tipo ${escape(tipo)}</code> ·
      real: lead = oportunidad del CRM en la ventana con <code>crm_contacts.attr_ad_id</code> (atribución nativa de GHL, persistida por Marketico desde 2026-08-21) · plan = primer <code>payment_plan</code> ≤60 d del lead · caja = cuotas pagadas · ROAS real solo en USD ·
      hook = vistas al 25% / plays (video_views de Meta es autoplay ≈ impresiones) · hold = vistas al 75% / vistas al 25% · «marca» = objetivo de marca o LPV ≤ 2% de los clics (tráfico al perfil, no a la landing) · miniaturas: caché local de <code>creativos_sync.sh</code> (Graph API, token de identities).
    </p>
  </div>
  </section>`;
}

module.exports = {
  id: "anuncios",
  // `orden` es presentación pura (se aplica en JS sobre las filas); el resto
  // son args de la fuente.
  manifest: { consumes: "rows", overridable: ["project", "from", "to", "tipo", "campaign", "min_spend", "limit", "orden"] },
  render: renderAnuncios,
};
