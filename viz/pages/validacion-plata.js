// validacion-plata page — el puntaje contra el criterio externo: PLATA.
//
// Las UIs anteriores del experimento comparan el instrumento consigo mismo
// (`bant-comparativo`: prompt vs prompt; `bant-variabilidad`: tirada vs
// tirada). Esta lo compara contra dinero que entró — cuotas pagadas — y por eso
// es la única que puede decir si el puntaje SIRVE.
//
// La pieza central no es una tabla sino el **eje de separación**: cada llamada
// es un punto sobre 0-100, lleno si pagó y hueco si no. Un puntaje que
// discrimina agrupa los llenos a la derecha; uno que no, los mezcla. Se pintan
// los dos ejes (v2 y producción) uno sobre otro para que la comparación sea
// visual antes que numérica — el AUC de arriba es ese dibujo, resumido.
//
// ⚠️ Muestra caso-control (10 que pagaron / 10 que no): el AUC es válido porque
// no depende de la prevalencia, pero la UI NUNCA debe presentar tasas de
// conversión por banda — no serían las del negocio. La advertencia va impresa.
//
// Consume `validacion_plata` (object) — bash/calls/validacion_plata.sh,
// read-only sobre la db local + Postgres. Sin filtros: es la lectura de un
// experimento cerrado.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const ITEMS = ["budget", "authority", "need", "timeline"];

function fmt(v, d = 1) {
  if (v == null) return "—";
  return Number(v).toFixed(d);
}

function money(v) {
  return "$" + Number(v || 0).toLocaleString("en-US", { maximumFractionDigits: 0 });
}

// Lectura del AUC con los cortes habituales. El color repite la semántica del
// DS (emerald=positivo, amber=precaución, red=no sirve).
function aucLectura(auc) {
  if (auc == null) return ["—", "text-slate-500"];
  if (auc >= 0.8) return ["discrimina bien", "text-emerald-700"];
  if (auc >= 0.7) return ["discrimina", "text-emerald-600"];
  if (auc >= 0.6) return ["débil", "text-amber-600"];
  return ["indistinguible del azar", "text-red-600"];
}

function pTexto(p) {
  if (p == null) return "—";
  if (p < 0.001) return "p<0.001";
  return "p=" + Number(p).toFixed(4).replace(/0+$/, "").replace(/\.$/, "");
}

// El eje de separación: un punto por llamada sobre 0-100. Lleno = pagó.
function ejeSeparacion(filas, clave, etiqueta, auc, p) {
  const pts = filas
    .map((f) => ({ v: clave === "v2" ? f.v2 : f.prod, pago: f.pago, id: f.id8, lead: f.lead, pagado: f.pagado }))
    .filter((x) => x.v != null);
  const [lectura, cls] = aucLectura(auc);
  const dots = pts
    .map((x) => {
      const base = "absolute top-1/2 -translate-y-1/2 -translate-x-1/2 rounded-full";
      const estilo = x.pago
        ? `background:var(--pos-solid);border:1px solid var(--pos-solid)`
        : `background:var(--surface-1);border:1.5px solid var(--text-3)`;
      const t = x.pago ? `${x.lead} — pagó ${money(x.pagado)}` : `${x.lead} — no pagó`;
      return `<span class="${base}" style="left:${x.v}%;width:11px;height:11px;${estilo};opacity:.9"
        title="${escape(t)} · ${fmt(x.v)}"></span>`;
    })
    .join("");
  return `<div class="mb-3">
    <div class="flex items-baseline gap-2 mb-1">
      <span class="text-xs font-medium" style="color:var(--text-1)">${escape(etiqueta)}</span>
      <span class="text-[11px] tabular-nums ${cls}">AUC ${fmt(auc, 3)} · ${escape(lectura)}</span>
      <span class="text-[11px] tabular-nums" style="color:var(--text-3)">${escape(pTexto(p))}</span>
    </div>
    <div class="relative h-6 rounded" style="background:var(--surface-3)">
      ${[25, 50, 75].map((x) => `<span class="absolute inset-y-0 border-l" style="left:${x}%;border-color:var(--border-1)"></span>`).join("")}
      ${dots}
    </div>
    <div class="flex justify-between text-[9px] mt-0.5" style="color:var(--text-3)">
      <span>0</span><span>25</span><span>50</span><span>75</span><span>100</span>
    </div>
  </div>`;
}

function kpiAuc(d, etiqueta, destacado) {
  const [lectura, cls] = aucLectura(d.auc);
  const borde = destacado ? "border-emerald-300" : "border-slate-200";
  return `<div class="rounded-lg border ${borde} p-3" style="background:var(--surface-1)">
    <p class="text-[10px] uppercase tracking-wide font-medium" style="color:var(--text-3)">${escape(etiqueta)}</p>
    <p class="text-2xl font-semibold tabular-nums ${cls}">${fmt(d.auc, 3)}</p>
    <p class="text-[11px] ${cls}">${escape(lectura)}</p>
    <p class="text-[11px] mt-1 tabular-nums" style="color:var(--text-2)">
      ${escape(pTexto(d.p_exacto))} <span style="color:var(--text-3)">(permutación exacta)</span></p>
    <p class="text-[11px] tabular-nums" style="color:var(--text-2)">
      media pagó <b>${fmt(d.media_pago)}</b> · no pagó <b>${fmt(d.media_no)}</b></p>
  </div>`;
}

function tablaItems(porItem) {
  const filas = porItem
    .map((d) => {
      const [lv] = aucLectura(d.v2.auc);
      const mejor = d.v2.auc != null && d.produccion.auc != null && d.v2.auc > d.produccion.auc;
      return `<tr class="border-t" style="border-color:var(--border-1)">
        <td class="px-2 py-1.5 text-[11px] font-medium" style="color:var(--text-1)">${escape(d.item)}</td>
        <td class="px-2 py-1.5 text-[11px] tabular-nums text-center ${mejor ? "text-emerald-700 font-semibold" : ""}"
          style="${mejor ? "" : "color:var(--text-1)"}">${fmt(d.v2.auc, 3)}</td>
        <td class="px-2 py-1.5 text-[11px] tabular-nums text-center" style="color:var(--text-2)">${fmt(d.produccion.auc, 3)}</td>
        <td class="px-2 py-1.5 text-[11px] tabular-nums text-center" style="color:var(--text-2)">
          ${fmt(d.v2.media_pago)} / ${fmt(d.v2.media_no)}</td>
        <td class="px-2 py-1.5 text-[11px] tabular-nums text-center" style="color:var(--text-3)">
          ${fmt(d.produccion.media_pago)} / ${fmt(d.produccion.media_no)}</td>
      </tr>`;
    })
    .join("");
  return `<div class="rounded-lg border border-slate-200 overflow-hidden" style="background:var(--surface-1)">
    <table class="w-full border-collapse">
      <thead><tr class="text-[9px] uppercase tracking-wide" style="background:var(--surface-2);color:var(--text-3)">
        <th class="px-2 py-1.5 text-left">ítem</th>
        <th class="px-2 py-1.5 text-center">AUC v2</th>
        <th class="px-2 py-1.5 text-center">AUC prod</th>
        <th class="px-2 py-1.5 text-center">v2 pagó/no</th>
        <th class="px-2 py-1.5 text-center">prod pagó/no</th>
      </tr></thead>
      <tbody>${filas}</tbody>
    </table>
  </div>`;
}

// Mini-barra 0-100 para un ítem dentro de la fila de la llamada.
function barra(v, baja) {
  if (v == null) return `<span class="text-[10px]" style="color:var(--text-3)">—</span>`;
  const cls = baja ? "bg-amber-400" : "bg-indigo-500";
  return `<span class="inline-flex items-center gap-1">
    <span class="relative inline-block h-1.5 w-10 rounded-full align-middle" style="background:var(--surface-3)">
      <span class="absolute inset-y-0 left-0 rounded-full ${cls}" style="width:${Math.max(0, Math.min(100, v))}%"></span>
    </span>
    <span class="text-[10px] tabular-nums ${baja ? "text-amber-700" : ""}"
      style="${baja ? "" : "color:var(--text-2)"}">${fmt(v, 0)}</span>
  </span>`;
}

function filaLlamada(f, i) {
  const baja = new Set(f.baja_confianza || []);
  const items = ITEMS.map((k) => `<td class="px-1.5 py-1.5 whitespace-nowrap">${barra(f.v2_items[k], baja.has(k))}</td>`).join("");
  const marca = f.pago
    ? `<span class="text-emerald-700 font-medium tabular-nums">${escape(money(f.pagado))}</span>`
    : `<span style="color:var(--text-3)">—</span>`;
  const fondo = f.pago ? "background:var(--surface-1)" : "background:var(--surface-2)";
  return `<tr class="border-t" style="border-color:var(--border-1);${fondo}">
    <td class="px-2 py-1.5 text-[10px] tabular-nums text-center" style="color:var(--text-3)">${i + 1}</td>
    <td class="px-2 py-1.5 whitespace-nowrap">
      <code class="text-[10px]" style="color:var(--text-3)">${escape(f.id8)}</code>
      <span class="text-[11px] ml-1.5" style="color:var(--text-1)">${escape(f.lead || "—")}</span>
    </td>
    <td class="px-2 py-1.5 text-[11px] tabular-nums text-center font-semibold" style="color:var(--text-1)">${fmt(f.v2)}</td>
    <td class="px-2 py-1.5 text-[11px] tabular-nums text-center" style="color:var(--text-3)">${fmt(f.prod)}</td>
    ${items}
    <td class="px-2 py-1.5 text-[11px] text-center">${marca}</td>
    <td class="px-2 py-1.5 text-[10px]" style="color:var(--text-3)">
      ${escape(f.arquetipo || "—")}${f.arq_unanime ? "" : ' <span class="text-amber-600">(2/3)</span>'}</td>
  </tr>`;
}

function renderValidacion(ui) {
  let d = null, fail = null;
  try {
    d = fetchSource(ui.source, ui.params || {}).rows[0] || {};
  } catch (e) {
    fail = e.message;
  }
  if (fail) {
    return `<section id="pane" class="flex-1 p-6">
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(fail)}</div>
    </section>`;
  }
  const filas = d.filas || [];
  const R = d.resumen || {};
  const v2 = R.v2_promedio || {}, prod = R.produccion_promedio || {};
  const emp = d.empates || {};
  const ban = d.banderas || {};
  const nPago = filas.filter((f) => f.pago).length;

  return `<section id="pane" class="flex-1 p-6 overflow-auto">
    <header class="mb-1 flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-semibold" style="color:var(--text-1)">${escape(ui.name)}</h1>
      <span class="text-xs" style="color:var(--text-3)">
        ${filas.length} llamadas · ${nPago} pagaron · pipeline de 3 tiradas · criterio externo: cuotas pagadas</span>
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
    </header>
    <p class="mb-3 text-xs max-w-4xl" style="color:var(--text-3)">
      La única vista del experimento que compara el puntaje contra algo que <b>no es otro puntaje</b>: plata que entró.
      <b>AUC</b> = probabilidad de que, tomando un lead que pagó y uno que no, el puntaje ordene bien ese par
      (0.5 = moneda al aire). El <b>p</b> es exacto, por permutación completa de las etiquetas.
    </p>

    <div class="grid gap-3 mb-4" style="grid-template-columns:repeat(auto-fit,minmax(15rem,1fr))">
      ${kpiAuc(v2, "v2 · mediana de 3 tiradas", true)}
      ${kpiAuc(prod, "producción · gemini, 1 tirada", false)}
      <div class="rounded-lg border border-slate-200 p-3" style="background:var(--surface-1)">
        <p class="text-[10px] uppercase tracking-wide font-medium" style="color:var(--text-3)">empates en el promedio</p>
        <p class="text-2xl font-semibold tabular-nums" style="color:var(--text-1)">${emp.v2 ?? "—"}
          <span class="text-sm" style="color:var(--text-3)">vs ${emp.produccion ?? "—"}</span></p>
        <p class="text-[11px]" style="color:var(--text-2)">v2 vs producción</p>
        <p class="text-[11px] mt-1" style="color:var(--text-3)">Un puntaje que empata no ordena una cola de leads.</p>
      </div>
      <div class="rounded-lg border border-slate-200 p-3" style="background:var(--surface-1)">
        <p class="text-[10px] uppercase tracking-wide font-medium" style="color:var(--text-3)">banderas del pipeline</p>
        <p class="text-2xl font-semibold tabular-nums text-amber-600">${ban.con_baja_confianza ?? 0}<span class="text-sm" style="color:var(--text-3)">/${filas.length}</span></p>
        <p class="text-[11px]" style="color:var(--text-2)">con ítem de baja confianza (rango &gt; 10 entre tiradas)</p>
        <p class="text-[11px] mt-1" style="color:var(--text-3)">arquetipo unánime 3/3: <b>${ban.arquetipo_unanime ?? 0}/${filas.length}</b></p>
      </div>
    </div>

    <div class="grid gap-4 mb-4" style="grid-template-columns:repeat(auto-fit,minmax(24rem,1fr))">
      <div class="rounded-lg border border-slate-200 p-3" style="background:var(--surface-1)">
        <h2 class="text-xs font-semibold mb-2" style="color:var(--text-1)">Separación sobre el eje 0-100</h2>
        ${ejeSeparacion(filas, "v2", "v2 · mediana de 3", v2.auc, v2.p_exacto)}
        ${ejeSeparacion(filas, "prod", "producción · gemini", prod.auc, prod.p_exacto)}
        <p class="text-[10px] mt-1" style="color:var(--text-3)">
          <span class="inline-block w-2.5 h-2.5 rounded-full align-middle" style="background:var(--pos-solid)"></span>
          pagó ·
          <span class="inline-block w-2.5 h-2.5 rounded-full align-middle" style="background:var(--surface-1);border:1.5px solid var(--text-3)"></span>
          no pagó. Si los llenos se agrupan a la derecha, el puntaje discrimina.
          Cada punto lleva su lead y su monto en el <i>tooltip</i>; el detalle completo
          está en la tabla de abajo, que es el gemelo legible de este dibujo.
        </p>
      </div>
      <div>
        <h2 class="text-xs font-semibold mb-2" style="color:var(--text-1)">Por ítem — dónde está la señal</h2>
        ${tablaItems(d.por_item || [])}
        <p class="text-[10px] mt-1.5" style="color:var(--text-3)">
          El caso de <b>need</b> es el hallazgo: producción puntúa casi igual a los que pagan y a los que no
          (el techo que motivó el eje de «costo de la inacción»); v2 los separa.
        </p>
      </div>
    </div>

    <h2 class="text-xs font-semibold mb-2" style="color:var(--text-1)">Las ${filas.length} llamadas, ordenadas por el puntaje v2</h2>
    <div class="rounded-lg border border-slate-200 overflow-x-auto" style="background:var(--surface-1)">
      <table class="w-full border-collapse min-w-[52rem]">
        <thead><tr class="text-[9px] uppercase tracking-wide" style="background:var(--surface-2);color:var(--text-3)">
          <th class="px-2 py-1.5">#</th>
          <th class="px-2 py-1.5 text-left">llamada</th>
          <th class="px-2 py-1.5 text-center">v2</th>
          <th class="px-2 py-1.5 text-center">prod</th>
          ${ITEMS.map((k) => `<th class="px-1.5 py-1.5 text-left">${escape(k)}</th>`).join("")}
          <th class="px-2 py-1.5 text-center">pagó</th>
          <th class="px-2 py-1.5 text-left">arquetipo</th>
        </tr></thead>
        <tbody>${filas.map(filaLlamada).join("")}</tbody>
      </table>
    </div>
    <p class="mt-1.5 text-[10px] max-w-4xl" style="color:var(--text-3)">
      Las barras en <span class="text-amber-700">ámbar</span> son ítems que el pipeline marcó de
      <b>baja confianza</b>: las 3 tiradas abrieron más de 10 puntos, así que ese número se lee como rango.
      Fila con fondo claro = el lead pagó.
    </p>

    <div class="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 max-w-4xl">
      <p class="text-[11px] text-amber-900">
        <b>Cómo NO leer esta tabla.</b> La muestra es <b>caso-control</b>: se escogieron a propósito 10 llamadas
        que pagaron y 10 que no, así que el 50% de conversión de aquí <b>no es el del negocio</b> y de esta vista
        no salen tasas de cierre por banda. El AUC sí es válido —no depende de la prevalencia—, y la medición fue
        ciega: los agentes que puntuaron solo vieron el transcript, y el desenlace ocurre después de la llamada.
        n=20: el orden de magnitud es sólido, el tercer decimal no.
      </p>
    </div>

    <p class="mt-2 text-[10px]" style="color:var(--text-3)">
      Fuente: <code>bash/calls/validacion_plata.sh</code> (AUC + permutación exacta) sobre la db local
      <code>generador_reportes</code> y <code>meeting_reports</code>; la verdad de plata la resuelve
      <code>bash/calls/conversion_real.sh</code> (ventana de 30 días + atribución única).
    </p>
  </section>`;
}

module.exports = {
  id: "validacion-plata",
  manifest: { consumes: "object", overridable: [] },
  render: renderValidacion,
};
