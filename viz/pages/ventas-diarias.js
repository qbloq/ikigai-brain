// ventas-diarias page — el RITMO diario de un proyecto desde las filas de
// bash/finance/ventas_diarias.sh: qué día entró más plata, cómo pinta la
// semana, cash vs pauta día a día. Nació del hueco #1 del contraste con el
// dashboard comercial (2026-08-21): el Cerebro tenía series mensuales
// (embudo, cuotas) y el diario solo de pauta; el «ventas diarias» con el
// mejor día y el % por día de la semana no existía.
//
// Reglas heredadas de la fuente (no se re-interpretan aquí): caja = cuotas
// pagadas por día Bogotá (nuevas = cuota 1, cuotas = n≥2); pauta solo USD;
// roas_dia = cash / pauta del MISMO día = lectura de ritmo, no atribución; la
// serie termina hoy. Todo lo agregado en esta página (mejor día, promedio,
// por día de semana) se calcula en JS sobre esas filas — un solo fetch.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");
const { chartEl } = require("../blocks/charts");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };
const DOW = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"];

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

function renderVentasDiarias(ui) {
  const p = ui.params || {};
  const { rows } = fetchSource(ui.source || "ventas_diarias", p);
  const dias = (rows || []).map((r) => ({ ...r, cash: Number(r.cash) || 0, spend_usd: Number(r.spend_usd) || 0 }));
  const n = dias.length;
  const sum = (k) => dias.reduce((a, r) => a + (Number(r[k]) || 0), 0);
  const cash = sum("cash"), spend = sum("spend_usd"), pagos = sum("pagos"), leads = sum("leads"), nuevas = sum("nuevas_amt"), cuotas = sum("cuotas_amt");
  const conVenta = dias.filter((r) => r.cash > 0).length;
  const mejor = dias.reduce((m, r) => (m == null || r.cash > m.cash ? r : m), null);
  const desde = dias[0]?.dia || p.from || "—", hasta = dias[n - 1]?.dia || p.to || "—";

  // --- por día de la semana: promedio de cash por día calendario (los ceros cuentan) ---
  const porDow = DOW.map((d, i) => {
    const ds = dias.filter((r) => Number(r.dow) === i + 1);
    const c = ds.reduce((a, r) => a + r.cash, 0);
    const best = ds.reduce((m, r) => (m == null || r.cash > m.cash ? r : m), null);
    return { dia_semana: d, dias: ds.length, cash: c, prom: ds.length ? c / ds.length : 0, pagos: ds.reduce((a, r) => a + (Number(r.pagos) || 0), 0), con_venta: ds.filter((r) => r.cash > 0).length, mejor: best };
  }).filter((r) => r.dias > 0);
  const mejorDow = porDow.reduce((m, r) => (m == null || r.prom > m.prom ? r : m), null);

  const cab = `
    ${kpi("Cash del período", usd(cash), { tone: "pos", sub: `${usd(nuevas)} nuevas + ${usd(cuotas)} cuotas · ${num(pagos)} pagos` })}
    ${kpi("Promedio / día", usd(n ? cash / n : 0), { sub: `${num(n)} días · ${num(conVenta)} con venta (${n ? Math.round((100 * conVenta) / n) : 0}%)` })}
    ${kpi("Mejor día", mejor ? usd(mejor.cash) : "—", { tone: "pos", sub: mejor ? `${mejor.dia} (${mejor.dia_semana}) · ${num(mejor.pagos)} pagos` : "" })}
    ${kpi("Mejor día de la semana", mejorDow ? escape(mejorDow.dia_semana) : "—", { sub: mejorDow ? `${usd(mejorDow.prom)} promedio · ${mejorDow.con_venta}/${mejorDow.dias} con venta` : "" })}
    ${kpi("Pauta (USD)", usd(spend), { sub: `${usd(n ? spend / n : 0)} / día` })}
    ${kpi("Cash / pauta", spend > 0 ? `${(Math.round((100 * cash) / spend) / 100).toLocaleString("es-CO")}x` : "—", { tone: spend > 0 && cash / spend >= 3.5 ? "pos" : "brand", sub: "del período, misma unidad que el ROAS real", title: "cash cobrado / pauta USD del período — ritmo, no atribución" })}
    ${kpi("Leads (CRM)", num(leads), { sub: `${(n ? leads / n : 0).toLocaleString("es-CO", { maximumFractionDigits: 1 })} / día · ${num(sum("ganadas"))} ganadas · ${num(sum("planes"))} planes` })}`;

  const serieSpec = n
    ? {
        kind: "line",
        labels: dias.map((r) => `${r.dia.slice(5)} ${r.dia_semana}`),
        series: [
          { label: "Cash cobrado (USD)", data: dias.map((r) => r.cash) },
          { label: "Pauta (USD)", data: dias.map((r) => r.spend_usd) },
        ],
      }
    : null;
  const tSerie = tbl(
    ["Día", "", "Nuevas", "Cuotas", "Cash", "Pauta", "Cash/pauta día", "Leads", "Ganadas", "Planes", "Contrato"],
    dias.map((r) => [
      `<span class="tabular-nums font-semibold">${escape(r.dia)}</span>`,
      `<span class="text-xs" style="color:${Number(r.dow) >= 6 ? TONE.muted : TONE.brand}">${escape(r.dia_semana)}</span>`,
      `<span class="tabular-nums">${num(r.nuevas_n)} · ${usd(r.nuevas_amt)}</span>`,
      `<span class="tabular-nums">${num(r.cuotas_n)} · ${usd(r.cuotas_amt)}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${mejor && r.dia === mejor.dia ? TONE.pos : r.cash > 0 ? "var(--text-1)" : TONE.muted}">${usd(r.cash)}</span>`,
      `<span class="tabular-nums">${usd(r.spend_usd)}</span>`,
      `<span class="tabular-nums" style="color:${r.roas_dia == null ? TONE.muted : Number(r.roas_dia) >= 3.5 ? TONE.pos : Number(r.roas_dia) >= 1 ? TONE.brand : TONE.neg}">${r.roas_dia == null ? "—" : `${Number(r.roas_dia).toLocaleString("es-CO")}x`}</span>`,
      `<span class="tabular-nums">${num(r.leads)}</span>`,
      `<span class="tabular-nums">${num(r.ganadas)}</span>`,
      `<span class="tabular-nums">${num(r.planes)}</span>`,
      `<span class="tabular-nums">${usd(r.contrato)}</span>`,
    ])
  );

  const dowSpec = porDow.length
    ? { kind: "bar", labels: porDow.map((r) => r.dia_semana), series: [{ label: "Cash promedio por día (USD)", data: porDow.map((r) => Math.round(r.prom)) }], sort: "none" }
    : null;
  const tDow = tbl(
    ["Día", "Días", "Con venta", "Cash total", "Promedio/día", "Pagos", "Mejor"],
    porDow.map((r) => [
      `<span class="font-semibold">${escape(r.dia_semana)}</span>`,
      `<span class="tabular-nums">${num(r.dias)}</span>`,
      `<span class="tabular-nums">${num(r.con_venta)}</span>`,
      `<span class="tabular-nums">${usd(r.cash)}</span>`,
      `<span class="tabular-nums font-semibold" style="color:${mejorDow && r.dia_semana === mejorDow.dia_semana ? TONE.pos : "var(--text-1)"}">${usd(r.prom)}</span>`,
      `<span class="tabular-nums">${num(r.pagos)}</span>`,
      `<span class="text-xs" style="color:var(--text-3)">${r.mejor ? `${escape(r.mejor.dia)} · ${usd(r.mejor.cash)}` : "—"}</span>`,
    ])
  );

  // OJO: `id="pane"` NO es decorativo — ver la nota en pages/lead-score.js.
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
  <div class="max-w-6xl mx-auto">
    <div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">Ventas diarias</h1>
      <span class="badge badge-neutral">${escape(String(p.project || "—"))}</span>
      <span class="badge badge-neutral">${escape(String(desde))} → ${escape(String(hasta))}</span>
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs" style="color:var(--text-brand)">abrir solo ↗</a>
    </div>
    <p class="mt-1 text-sm" style="color:var(--text-3)">
      La caja por día (cuotas pagadas, día Bogotá) contra la pauta del mismo día. El ritmo, no la atribución:
      el cash de hoy viene de pauta de antes — el ROAS atribuido vive en el embudo.
    </p>

    <div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(10rem,1fr))">${cab}</div>

    ${section("Cash vs pauta, día a día", "misma unidad (USD): la brecha entre las dos líneas es lo que el canal deja cada día")}
    ${chartCard(serieSpec, "showserie", tSerie)}

    ${section("Por día de la semana", "promedio por día calendario (los días en cero cuentan) — dónde se concentra la venta")}
    <div class="grid gap-4" style="grid-template-columns:repeat(auto-fit,minmax(22rem,1fr))">
      ${chartCard(dowSpec, "showdow", tDow)}
    </div>

    <p class="mt-10 text-xs" style="color:var(--text-3)">
      Fuente: <code>bash/finance/ventas_diarias.sh --project "${escape(String(p.project || ""))}"</code> ·
      nuevas = cuota 1, cuotas = n≥2; pauta solo USD; la serie termina hoy aunque la ventana sea el mes entero.
    </p>
  </div>
  </section>`;
}

module.exports = {
  id: "ventas-diarias",
  manifest: { consumes: "rows", overridable: ["project", "from", "to"] },
  render: renderVentasDiarias,
};
