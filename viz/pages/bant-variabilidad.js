// bant-variabilidad page — el test-retest del reporte de llamada: la misma
// llamada, el mismo prompt (mejorado-2), CINCO tiradas en contextos limpios.
//
// La pregunta que responde: ¿cuánto del puntaje es el LEAD y cuánto es el DADO?
// El reporte lo produce un LLM, así que una corrida es una muestra de una
// distribución. Este panel pinta esa distribución:
//
//   · KPIs por ítem — ICC (fracción de la varianza que es del lead), sd_intra
//     (el ruido del proceso) y la diferencia mínima detectable (2.77·sd_intra:
//     dos leads que difieren menos que eso en UNA corrida son indistinguibles).
//   · Por llamada — una tira 0-100 por ítem con un punto por tirada: si los
//     puntos se apiñan, el proceso es estable; si se dispersan, es ruido.
//     Los números van al lado (la tira es la forma, no el dato).
//   · Arquetipos — el consenso entre tiradas, con su conteo cuando difieren.
//
// Consume `bant_variabilidad` (object) — bash/calls/variabilidad_bant.sh,
// read-only sobre la db local. Sin filtros y sin writes: es un instrumento de
// lectura de un experimento cerrado, no una vista operativa.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const ITEMS = ["budget", "authority", "need", "timeline"];
const ITEM_CLS = {
  budget: { dot: "bg-sky-500", txt: "text-sky-700" },
  authority: { dot: "bg-violet-500", txt: "text-violet-700" },
  need: { dot: "bg-pink-500", txt: "text-pink-700" },
  timeline: { dot: "bg-amber-500", txt: "text-amber-700" },
};

function fmt(v) {
  if (v == null) return "—";
  return Number.isInteger(v) ? String(v) : v.toFixed(1);
}

function iccBadge(icc) {
  // Cortes estándar de lectura de ICC; el color repite la semántica del DS
  // (emerald=positivo, amber=precaución, red=negativo).
  if (icc >= 0.9) return ["excelente", "bg-emerald-100 text-emerald-800"];
  if (icc >= 0.75) return ["buena", "bg-emerald-50 text-emerald-700"];
  if (icc >= 0.5) return ["moderada", "bg-amber-50 text-amber-700"];
  return ["pobre — el ruido domina", "bg-red-50 text-red-700"];
}

// La tira 0-100 con un punto por tirada. Puntos repetidos en el mismo valor se
// apilan con un halo para que N tiradas idénticas no se vean como una sola.
function tira(scores, dotCls) {
  const conteo = {};
  for (const s of scores) conteo[s] = (conteo[s] || 0) + 1;
  const puntos = Object.entries(conteo).map(([v, n]) =>
    `<span class="absolute top-1/2 -translate-y-1/2 -translate-x-1/2 rounded-full ${dotCls}"
       style="left:${Number(v)}%;width:${n > 1 ? 11 : 8}px;height:${n > 1 ? 11 : 8}px;
              ${n > 1 ? "outline:2px solid var(--surface-1);" : ""}opacity:.85"
       title="${escape(String(v))} × ${n} tirada${n > 1 ? "s" : ""}"></span>`).join("");
  const min = Math.min(...scores), max = Math.max(...scores);
  const rango = max > min
    ? `<span class="absolute top-1/2 -translate-y-1/2 h-[3px] rounded ${dotCls} opacity-30"
        style="left:${min}%;width:${max - min}%"></span>` : "";
  return `<div class="relative h-4 rounded-full" style="background:var(--surface-3)">
    <span class="absolute inset-y-0 border-l" style="left:50%;border-color:var(--border-1)"></span>
    ${rango}${puntos}
  </div>`;
}

function filaItem(L, item) {
  const it = L.items[item];
  if (!it) return "";
  const c = ITEM_CLS[item];
  const estable = it.rango <= 10;
  return `<tr class="align-middle">
    <td class="px-2 py-1 text-[11px] font-medium whitespace-nowrap ${c.txt}">${escape(item)}</td>
    <td class="px-2 py-1 w-full min-w-56">${tira(it.scores, c.dot)}</td>
    <td class="px-2 py-1 text-[11px] tabular-nums whitespace-nowrap" style="color:var(--text-2)">
      ${it.scores.map(fmt).join(" · ")}</td>
    <td class="px-2 py-1 text-[11px] tabular-nums text-center" style="color:var(--text-1)"><b>${fmt(it.media)}</b></td>
    <td class="px-2 py-1 text-[11px] tabular-nums text-center" style="color:var(--text-2)">${fmt(it.sd)}</td>
    <td class="px-2 py-1 text-[11px] tabular-nums text-center ${estable ? "text-emerald-600" : "text-amber-600"}">${fmt(it.rango)}</td>
  </tr>`;
}

function tarjetaLlamada(L) {
  const a = L.arquetipos;
  const consenso = a.consenso == null ? "—"
    : a.distintos === 1
      ? `<span class="text-emerald-600">unánime</span>`
      : `<span class="text-amber-600">${a.distintos} etiquetas</span>
         <span style="color:var(--text-3)">(${escape(Object.entries(a.conteo).map(([k, n]) => `${k} ×${n}`).join(" · "))})</span>`;
  return `<div class="rounded-lg border border-slate-200 mb-3 overflow-hidden" style="background:var(--surface-1)">
    <div class="px-3 py-2 flex flex-wrap items-baseline gap-x-3 gap-y-0.5" style="background:var(--surface-2)">
      <code class="text-[10px]" style="color:var(--text-3)">${escape(L.id8)}</code>
      <span class="text-sm font-medium" style="color:var(--text-1)">${escape(L.lead || "—")}</span>
      <span class="text-[11px]" style="color:var(--text-3)">${escape(L.fecha || "")} · ${L.n_tiradas} tiradas</span>
      <span class="ml-auto text-[11px]">arquetipo: <b>${escape(a.moda || "—")}</b> — ${consenso}</span>
    </div>
    <table class="w-full border-collapse">
      <thead><tr class="text-[9px] uppercase tracking-wide" style="color:var(--text-3)">
        <th class="px-2 pt-1.5 text-left">ítem</th>
        <th class="px-2 pt-1.5 text-left">tiradas sobre 0-100</th>
        <th class="px-2 pt-1.5 text-left">valores</th>
        <th class="px-2 pt-1.5 text-center">media</th>
        <th class="px-2 pt-1.5 text-center">sd</th>
        <th class="px-2 pt-1.5 text-center">rango</th>
      </tr></thead>
      <tbody>${ITEMS.map((i) => filaItem(L, i)).join("")}</tbody>
    </table>
  </div>`;
}

function kpiItem(p) {
  const [lectura, cls] = iccBadge(p.icc);
  const c = ITEM_CLS[p.item];
  return `<div class="rounded-lg border border-slate-200 p-3" style="background:var(--surface-1)">
    <p class="text-[10px] uppercase tracking-wide font-medium ${c.txt}">${escape(p.item)}</p>
    <p class="text-2xl font-semibold tabular-nums" style="color:var(--text-1)">${p.icc.toFixed(2)}
      <span class="text-[10px] px-1.5 py-0.5 rounded align-middle ${cls}">${escape(lectura)}</span></p>
    <p class="text-[10px]" style="color:var(--text-3)">ICC — fracción de la varianza que es del lead</p>
    <p class="text-[11px] mt-1.5" style="color:var(--text-2)">
      ruido (sd intra) <b class="tabular-nums">${fmt(p.sd_intra)}</b> ·
      señal (sd inter) <b class="tabular-nums">${fmt(p.sd_inter)}</b></p>
    <p class="text-[11px]" style="color:var(--text-2)">
      mínimo distinguible <b class="tabular-nums">±${fmt(p.diferencia_minima_detectable)}</b></p>
  </div>`;
}

function renderVariabilidad(ui) {
  let d = null, fail = null;
  try {
    // fetchSource siempre envuelve en {rows:[...]}; una fuente `object` llega
    // como rows[0] (misma convención que task_detail/call_detail).
    d = fetchSource(ui.source, ui.params || {}).rows[0] || {};
  } catch (e) {
    fail = e.message;
  }
  if (fail) {
    return `<section id="pane" class="flex-1 p-6">
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(fail)}</div>
    </section>`;
  }
  const g = d.global || {};
  const llamadas = (d.llamadas || []).filter((L) => L.n_tiradas > 0);

  return `<section id="pane" class="flex-1 p-6 overflow-auto">
    <header class="mb-1 flex items-baseline gap-3">
      <h1 class="text-xl font-semibold" style="color:var(--text-1)">${escape(ui.name)}</h1>
      <span class="text-xs" style="color:var(--text-3)">${g.n_llamadas || 0} llamadas · ${g.n_tiradas || 0} tiradas · prompt ${escape(g.prompt || "")} · muestreo aleatorio semilla ${escape(g.semilla_muestreo || "")}</span>
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
    </header>
    <p class="mb-3 text-xs max-w-4xl" style="color:var(--text-3)">
      La misma llamada, el mismo prompt, cinco corridas en contextos limpios. El reporte lo produce un LLM,
      así que <b>una corrida es una muestra de una distribución</b> — este panel mide esa distribución.
      <b>ICC</b> = qué fracción de la varianza distingue leads (señal) y no tiradas (ruido).
      <b>Mínimo distinguible</b> = 2.77·sd_intra: dos leads cuyos puntajes de una sola corrida difieren
      menos que eso son indistinguibles del azar — es el margen con el que hay que leer TODA la tabla
      comparativa, y también los reportes de producción, que son una tirada única.
    </p>

    <div class="grid gap-3 mb-4" style="grid-template-columns:repeat(auto-fit,minmax(13rem,1fr))">
      ${(d.por_item || []).map(kpiItem).join("")}
    </div>

    ${llamadas.map(tarjetaLlamada).join("")}

    <p class="mt-1 text-[11px] max-w-4xl" style="color:var(--text-3)">
      Cada punto es una tirada; un punto grande con halo son varias tiradas con el mismo valor
      (el título dice cuántas). La franja tenue es el rango. Rango en <span class="text-emerald-600">verde</span> ≤ 10 puntos,
      en <span class="text-amber-600">ámbar</span> mayor. Fuente: <code>bash/calls/variabilidad_bant.sh</code>
      (read-only sobre la db local <code>reportes_llamada</code>, tabla <code>muestra3</code> + corridas <code>*-mejorado2-t*</code>).
    </p>
  </section>`;
}

module.exports = {
  id: "bant-variabilidad",
  manifest: { consumes: "object", overridable: [] },
  render: renderVariabilidad,
};
