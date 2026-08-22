// ventas-precio page — «Ventas por programa antes y después de los cambios de
// precio»: el entregable de la tarea 332c414a (pedido de Lorenzo en la
// alineación DG 2026-08-19) como UI, para quien no lee Markdown.
//
// Las dos tablas viven en el CONTRATO de la tarea como artefactos «SQL
// Results» y se ejecutan en vivo (fuente `io_query`): `params.io` = el output
// (distribución por período) y `params.io_serie` = el input (planes por mes y
// programa). Nada se digita: los KPIs y la comparación entre períodos se
// calculan en JS sobre esas filas. La narrativa (qué se pidió, lectura,
// cautelas) es copy curado y va en `params.texto` del spec — se cambia
// re-publicando, no en código (misma regla que `params.titulares` de angulos).
//
// Semántica heredada del artefacto: unidad = plan de pago iniciado (la venta
// firmada); contrato = valor del plan; cobrado = cuotas pagadas a hoy (NO
// comparable entre períodos por edad de los planes: se muestra, no se compara).

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");
const { chartEl } = require("../blocks/charts");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };
const PROGRAMAS = ["premium mastermind", "premium mastermind lite", "premium academy 3 meses", "premium academy 6 meses"];
const NOMBRE = {
  "premium mastermind": "Premium Mastermind",
  "premium mastermind lite": "Premium Mastermind Lite",
  "premium academy 3 meses": "Premium Academy 3 meses",
  "premium academy 6 meses": "Premium Academy 6 meses",
};

const n0 = (v) => (v == null || v === "" || Number.isNaN(Number(v)) ? 0 : Number(v));
const num = (v, d = 0) => (v == null || v === "" ? "—" : n0(v).toLocaleString("es-CO", { maximumFractionDigits: d, minimumFractionDigits: d }));
const usd = (v) => (v == null || v === "" ? "—" : "$" + Math.round(n0(v)).toLocaleString("es-CO"));
const pct = (v) => (v == null || v === "" ? "—" : `${num(v, 1)} %`);
const delta = (a, b, fmt = (x) => num(x, 1)) => {
  if (!a) return "";
  const d = ((b - a) / a) * 100;
  const col = Math.abs(d) < 5 ? TONE.muted : d > 0 ? TONE.pos : TONE.neg;
  return `<span class="text-xs tabular-nums" style="color:${col}">${d > 0 ? "+" : ""}${num(d, 0)} %</span>`;
};
// Normaliza el nombre del programa a su familia (Academy 6 meses y «6 meses $1k» son el mismo programa con precio nuevo).
function familia(p) {
  const s = String(p || "").toLowerCase().trim();
  if (s.startsWith("premium academy 6 meses")) return "premium academy 6 meses";
  return s;
}

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
// Un bloque de texto curado: párrafos separados por línea en blanco; «**x**» → negrita.
function prosa(txt) {
  if (!txt) return "";
  return String(txt)
    .split(/\n\s*\n/)
    .map((p) => `<p class="text-sm mt-2" style="color:var(--text-2)">${escape(p.trim()).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")}</p>`)
    .join("");
}
function lista(items) {
  if (!items || !items.length) return "";
  return `<ol class="mt-2 pl-5 list-decimal">${items.map((t) => `<li class="text-sm mt-1.5" style="color:var(--text-2)">${escape(t).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")}</li>`).join("")}</ol>`;
}

function render(ui) {
  const p = ui.params || {};
  const texto = p.texto || {};
  let rows = [], serie = [], err = "";
  try {
    rows = fetchSource("io_query", { io: p.io, limit: "0" }).rows || [];
    if (p.io_serie) serie = fetchSource("io_query", { io: p.io_serie, limit: "0" }).rows || [];
  } catch (e) {
    err = e.message;
  }

  // --- períodos: totales y por programa (familias) ---
  const eras = [...new Set(rows.map((r) => r.era))].sort();
  const porEra = eras.map((era) => {
    const rs = rows.filter((r) => r.era === era);
    const planes = rs.reduce((a, r) => a + n0(r.planes), 0);
    const contrato = rs.reduce((a, r) => a + n0(r.contrato), 0);
    const cobrado = rs.reduce((a, r) => a + n0(r.cobrado), 0);
    const meses = n0(rs[0]?.meses_era) || 1;
    const fam = {};
    for (const r of rs) {
      const f = familia(r.programa);
      fam[f] = fam[f] || { planes: 0, contrato: 0, cobrado: 0, precio: null };
      fam[f].planes += n0(r.planes); fam[f].contrato += n0(r.contrato); fam[f].cobrado += n0(r.cobrado);
      if (fam[f].precio == null || n0(r.planes) > (fam[f]._n || 0)) { fam[f].precio = r.precio_moda; fam[f]._n = n0(r.planes); }
    }
    return { era, label: String(era).replace(/^\d+·\s*/, ""), corto: `P${String(era).charAt(0)}`, planes, contrato, cobrado, meses, ticket: planes ? contrato / planes : 0, planes_mes: planes / meses, contrato_mes: contrato / meses, fam };
  });
  const first = porEra[0], last = porEra[porEra.length - 1], prev = porEra[porEra.length - 2] || first;

  // --- KPIs de cabecera: el último período contra el anterior ---
  const cab = last
    ? `
    ${kpi(`Planes / mes · ${last.corto}`, num(last.planes_mes, 1), { sub: `${prev.corto}: ${num(prev.planes_mes, 1)} ${delta(prev.planes_mes, last.planes_mes)}`, title: "Planes de pago iniciados por mes en el período vigente vs el anterior" })}
    ${kpi(`Contrato / mes · ${last.corto}`, usd(last.contrato_mes), { tone: last.contrato_mes >= prev.contrato_mes ? "pos" : "neg", sub: `${prev.corto}: ${usd(prev.contrato_mes)} ${delta(prev.contrato_mes, last.contrato_mes)}`, title: "Valor de contrato firmado por mes" })}
    ${kpi(`Ticket promedio · ${last.corto}`, usd(last.ticket), { tone: last.ticket >= prev.ticket ? "pos" : "neg", sub: `${prev.corto}: ${usd(prev.ticket)} ${delta(prev.ticket, last.ticket)}`, title: "Contrato promedio por plan — refleja la MEZCLA de programas, no solo el precio" })}
    ${(() => { const f = "premium mastermind"; const a = prev.fam[f], b = last.fam[f]; const am = a ? a.planes / prev.meses : 0, bm = b ? b.planes / last.meses : 0; return kpi(`Mastermind / mes · ${last.corto}`, num(bm, 1), { tone: bm >= am ? "pos" : "neg", sub: `${prev.corto}: ${num(am, 1)} ${delta(am, bm)} · precio ${usd(b?.precio)}`, title: "El programa grande: ritmo mensual antes y después del último cambio de precio" }); })()}
    ${(() => { const f = "premium mastermind lite"; const a = prev.fam[f], b = last.fam[f]; const am = a ? a.planes / prev.meses : 0, bm = b ? b.planes / last.meses : 0; return kpi(`Lite / mes · ${last.corto}`, num(bm, 1), { tone: bm >= am * 0.95 ? "pos" : "neg", sub: `${prev.corto}: ${num(am, 1)} ${delta(am, bm)} · precio ${usd(b?.precio)}`, title: "El programa del medio: ritmo mensual antes y después" }); })()}
    ${(() => { const f = "premium academy 3 meses"; const a = prev.fam[f], b = last.fam[f]; const am = a ? a.planes / prev.meses : 0, bm = b ? b.planes / last.meses : 0; return kpi(`Academy 3m / mes · ${last.corto}`, num(bm, 1), { sub: `${prev.corto}: ${num(am, 1)} ${delta(am, bm)} · precio ${usd(b?.precio)}`, title: "El programa de entrada: ritmo mensual antes y después" }); })()}`
    : "";

  // --- gráfica: planes/mes por programa y período ---
  const mixSpec = porEra.length
    ? {
        kind: "bar",
        labels: PROGRAMAS.map((f) => NOMBRE[f]),
        series: porEra.map((e) => ({ label: `${e.corto} · ${e.label}`, data: PROGRAMAS.map((f) => Math.round(((e.fam[f]?.planes || 0) / e.meses) * 10) / 10) })),
        sort: "none",
      }
    : null;
  const tMix = tbl(
    ["Programa", ...porEra.flatMap((e) => [`${e.corto} planes (%)`, `${e.corto} /mes`, `${e.corto} precio`])],
    PROGRAMAS.map((f) => [
      `<span class="font-semibold">${escape(NOMBRE[f])}</span>`,
      ...porEra.flatMap((e) => {
        const x = e.fam[f];
        return [
          `<span class="tabular-nums">${x ? `${num(x.planes)} (${num((100 * x.planes) / e.planes, 0)} %)` : "—"}</span>`,
          `<span class="tabular-nums font-semibold">${x ? num(x.planes / e.meses, 1) : "—"}</span>`,
          `<span class="tabular-nums" style="color:var(--text-3)">${x ? usd(x.precio) : "—"}</span>`,
        ];
      }),
    ])
  );

  // --- tabla de períodos (totales) ---
  const tEras = tbl(
    ["Período", "Meses", "Planes", "Planes / mes", "Contrato", "Contrato / mes", "Ticket", "Cobrado a hoy"],
    porEra.map((e) => [
      `<span class="font-semibold">${escape(e.corto)}</span> <span class="text-xs" style="color:var(--text-3)">${escape(e.label)}</span>`,
      `<span class="tabular-nums">${num(e.meses, 1)}</span>`,
      `<span class="tabular-nums">${num(e.planes)}</span>`,
      `<span class="tabular-nums font-semibold">${num(e.planes_mes, 1)}</span>`,
      `<span class="tabular-nums">${usd(e.contrato)}</span>`,
      `<span class="tabular-nums font-semibold">${usd(e.contrato_mes)}</span>`,
      `<span class="tabular-nums">${usd(e.ticket)}</span>`,
      `<span class="tabular-nums" style="color:var(--text-3)" title="No comparable entre períodos: los planes recientes llevan menos cuotas">${usd(e.cobrado)} (${num((100 * e.cobrado) / (e.contrato || 1), 0)} %)</span>`,
    ])
  );

  // --- participación en contrato por período ---
  const tShare = tbl(
    ["Programa", ...porEra.flatMap((e) => [`${e.corto} contrato (%)`, `${e.corto} ticket`])],
    PROGRAMAS.map((f) => [
      `<span class="font-semibold">${escape(NOMBRE[f])}</span>`,
      ...porEra.flatMap((e) => {
        const x = e.fam[f];
        return [
          `<span class="tabular-nums">${x ? `${usd(x.contrato)} (${num((100 * x.contrato) / e.contrato, 0)} %)` : "—"}</span>`,
          `<span class="tabular-nums" style="color:var(--text-3)">${x && x.planes ? usd(x.contrato / x.planes) : "—"}</span>`,
        ];
      }),
    ])
  );

  // --- serie mensual (del input del contrato) ---
  const meses = [...new Set(serie.map((r) => r.mes))].sort();
  const serieFam = meses.map((m) => {
    const rs = serie.filter((r) => r.mes === m);
    const o = { mes: m, total: rs.reduce((a, r) => a + n0(r.planes), 0), contrato: rs.reduce((a, r) => a + n0(r.contrato), 0) };
    for (const f of PROGRAMAS) {
      const fr = rs.filter((r) => familia(r.programa) === f);
      o[f] = { planes: fr.reduce((a, r) => a + n0(r.planes), 0), precio: fr.sort((a, b) => n0(b.planes) - n0(a.planes))[0]?.precio_moda };
    }
    return o;
  });
  const serieSpec = serieFam.length
    ? { kind: "line", labels: serieFam.map((r) => r.mes), series: PROGRAMAS.map((f) => ({ label: NOMBRE[f], data: serieFam.map((r) => r[f].planes) })) }
    : null;
  const tSerie = tbl(
    ["Mes", ...PROGRAMAS.map((f) => NOMBRE[f]), "Total", "Contrato"],
    serieFam.map((r) => [
      `<span class="tabular-nums font-semibold">${escape(r.mes)}</span>`,
      ...PROGRAMAS.map((f) => `<span class="tabular-nums">${num(r[f].planes)}${r[f].planes ? ` <span class="text-xs" style="color:var(--text-3)">· ${usd(r[f].precio)}</span>` : ""}</span>`),
      `<span class="tabular-nums font-semibold">${num(r.total)}</span>`,
      `<span class="tabular-nums">${usd(r.contrato)}</span>`,
    ])
  );

  const cambios = (texto.cambios || []).map((c) => [
    `<span class="tabular-nums font-semibold">${escape(c.fecha || "")}</span>`,
    `<span>${escape(c.programa || "")}</span>`,
    `<span class="tabular-nums">${escape(c.antes || "")} → <b>${escape(c.despues || "")}</b></span>`,
    `<span class="text-xs" style="color:var(--text-3)">${escape(c.nota || "")}</span>`,
  ]);

  // OJO: `id="pane"` NO es decorativo — el servidor parchea por SSE sobre ese id.
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
  <div class="max-w-6xl mx-auto">
    <div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">${escape(ui.name)}</h1>
      <span class="badge badge-neutral">${escape(String(p.project || "David Guerrero"))}</span>
      ${first && last ? `<span class="badge badge-neutral">${escape(first.label.split(" → ")[0])} → hoy</span>` : ""}
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs" style="color:var(--text-brand)">abrir solo ↗</a>
    </div>
    <p class="mt-1 text-sm" style="color:var(--text-3)">
      ${escape(texto.subtitulo || "Qué se vendió con cada lista de precios: planes de pago iniciados por programa, antes y después de cada cambio de precio. Datos en vivo — se recalculan al abrir.")}
    </p>
    ${err ? `<div class="alert alert-neg text-sm mt-4">${escape(err)}</div>` : ""}

    <div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">${cab}</div>

    ${texto.pedido ? `${section("Qué se pidió", texto.pedido_fuente || "")}<div class="card card-pad">${prosa(texto.pedido)}</div>` : ""}

    ${section("Los cambios de precio", "detectados en los datos: el día en que cambia el precio dominante de cada programa")}
    ${cambios.length ? tbl(["Corte", "Programa", "Precio", "Cómo se ve"], cambios) : ""}

    ${section("Ritmo por programa en cada período", "planes iniciados por mes — la unidad que deja comparar períodos de distinta duración")}
    ${chartCard(mixSpec, "showmix", tMix)}

    ${section("Totales por período", "")}
    ${tEras}

    ${section("Participación en el contrato", "cuánto del valor firmado pone cada programa, y su ticket")}
    ${tShare}

    ${texto.lectura && texto.lectura.length ? `${section("Lectura", "")}<div class="card card-pad">${lista(texto.lectura)}</div>` : ""}

    ${section("Serie mensual", "planes iniciados por mes y programa, con el precio dominante del mes")}
    ${chartCard(serieSpec, "showserie", tSerie)}

    ${texto.cautelas && texto.cautelas.length ? `${section("Cautelas", "")}<div class="card card-pad">${lista(texto.cautelas)}</div>` : ""}

    <p class="mt-10 text-xs" style="color:var(--text-3)">
      ${escape(texto.pie || "Unidad: plan de pago iniciado (la venta firmada). Contrato = valor del plan; ticket = contrato promedio; cobrado = cuotas pagadas a hoy (no comparable entre períodos). Las tablas se ejecutan en vivo desde el contrato de la tarea 332c414a.")}
    </p>
  </div>
  </section>`;
}

module.exports = {
  id: "ventas-precio",
  manifest: { consumes: "rows", overridable: [] },
  render,
};
