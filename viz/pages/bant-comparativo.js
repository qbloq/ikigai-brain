// bant-comparativo page — el cuadro del experimento de prompt, lado a lado.
//
// Cada LEAD ocupa una fila que se parte en cuatro, una por celda del cuadro:
//
//     Lead ┬ producción · gemini-2.5-flash   ← el control: lo que corre HOY
//          ├ producción · claude             ← mismo prompt, otro modelo
//          ├ mejorado   · claude             ← rúbrica genérica + enum
//          └ mejorado-2 · claude             ← + eje propio para `need`
//
// La cuarta existe porque la rúbrica de `mejorado` arregló budget, authority y
// timeline y dejó `need` clavado en 90 (−1.7 en pareado): sus anclas piden que
// el lead lo haya dicho explícitamente, y agendar la llamada ya es decirlo.
//
// Las cuatro celdas se pintan SIEMPRE. Una celda que falta no desaparece de la
// tabla: queda vacía y con el handle para mandarla a correr, porque el hueco
// es la mitad de la información (a esta muestra le faltan corridas, y eso hay
// que poderlo ver sin consultar otra cosa).
//
// El botón NO genera el reporte — generarlo es una corrida de LLM, no un
// script. Copia el handle al portapapeles y el usuario lo dicta en la
// conversación (`viz es visor, la edición es la conversación`). Por eso este
// componente NO declara `manifest.writes`: no escribe nada, en ningún lado.
//
// Consume `bant_comparativo` (rows), una fila por llamada con `celdas[]`.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

// Las bandas del puntaje. Existen para que el TECHO se vea: en producción el
// 60% de los puntajes no nulos cae en 90-100, y una tabla de números crudos
// esconde exactamente eso. El color no es decoración, es el hallazgo.
function banda(v) {
  if (v == null) return ["text-slate-300", "—"];
  if (v >= 90) return ["bg-emerald-100 text-emerald-800 font-semibold", fmt(v)];
  if (v >= 70) return ["bg-sky-50 text-sky-700", fmt(v)];
  if (v >= 40) return ["bg-amber-50 text-amber-700", fmt(v)];
  if (v > 0) return ["bg-red-50 text-red-700", fmt(v)];
  return ["bg-slate-100 text-slate-400", "0"];
}

function fmt(v) {
  if (v == null) return "—";
  return Number.isInteger(v) ? String(v) : v.toFixed(1);
}

function puntaje(v) {
  const [cls, txt] = banda(v);
  return `<td class="px-1.5 py-1 text-center text-xs tabular-nums ${cls}">${txt}</td>`;
}

const CELDA_CLS = {
  "produccion-gemini": "text-slate-500",
  "produccion-claude": "text-violet-600",
  "mejorado-claude": "text-indigo-600 font-medium",
  "mejorado2-claude": "text-pink-600 font-medium",
};

// Delta por fila, y SIEMPRE contra el antecesor que aísla un solo cambio:
//   mejorado   → contra claude·producción (mismo modelo: mide el prompt), y
//                contra gemini solo como respaldo, dicho en el tooltip.
//   mejorado-2 → contra mejorado (lo único que cambia entre ambos es `need`).
// Nunca mezclados en un mismo número: un delta entre modelos distintos mide
// otra cosa que un delta entre prompts.
function deltaCell(r, celda) {
  if (celda === "mejorado2-claude") {
    const d = r.delta_v2_vs_v1;
    if (d == null) return `<td class="px-1.5 py-1 text-center text-slate-300 text-xs">—</td>`;
    const cls = d < 0 ? "text-red-600" : d > 0 ? "text-emerald-600" : "text-slate-400";
    return `<td class="px-1.5 py-1 text-center text-xs tabular-nums ${cls} whitespace-nowrap"
      title="vs mejorado (el eje de need)">${d > 0 ? "+" : ""}${fmt(d)}</td>`;
  }
  if (celda !== "mejorado-claude") return `<td class="px-1.5 py-1"></td>`;
  const d = r.delta_vs_claude != null ? r.delta_vs_claude : r.delta_vs_gemini;
  const contra = r.delta_vs_claude != null ? "vs claude·prod" : "vs gemini";
  if (d == null) return `<td class="px-1.5 py-1 text-center text-slate-300 text-xs">—</td>`;
  const cls = d < 0 ? "text-red-600" : d > 0 ? "text-emerald-600" : "text-slate-400";
  return `<td class="px-1.5 py-1 text-center text-xs tabular-nums ${cls} whitespace-nowrap"
    title="${escape(contra)}">${d > 0 ? "+" : ""}${fmt(d)}</td>`;
}

// La celda que falta. Un botón que copia el handle — no un @post: no hay
// script que genere un reporte.
function faltante(r, c) {
  if (!c.handle) {
    return `<td colspan="9" class="px-2 py-1.5 text-xs" style="color:var(--text-3)">
      <span class="italic">${escape(c.motivo || "no disponible")}</span></td>`;
  }
  const key = `${r.id8}-${c.celda}`;
  const cmd = escape(c.handle);
  return `<td colspan="9" class="px-2 py-1.5">
    <button data-on:click="navigator.clipboard.writeText('${cmd}');$copiado='${key}'"
      class="text-[11px] px-2 py-0.5 rounded-md border border-indigo-300 text-indigo-600 hover:bg-indigo-50 whitespace-nowrap"
      title="Copia el handle; dícteselo al cerebro en la conversación">▶ generar</button>
    <code class="ml-2 text-[10px]" style="color:var(--text-3)">${cmd}</code>
    <span data-show="$copiado=='${key}'" class="ml-2 text-[10px] text-emerald-600">✓ copiado — pégalo en el chat</span>
  </td>`;
}

// Las bandas, explicadas. No es decoración documentada: el color de la tabla
// son los MISMOS cortes que las anclas del prompt mejorado, así que la leyenda
// es la rúbrica. Y la fila de producción no tiene rúbrica ninguna — ahí el
// color describe la salida, no un criterio. Eso es justo lo que hay que poder
// leer sin abrir el prompt.
const BANDAS = [
  ["≥ 90", "bg-emerald-100 text-emerald-800",
   "Lo dijo explícito y sin ambigüedad, y lo respaldó con un hecho concreto: un monto, una fecha, o algo que ya hizo."],
  ["70 - 89", "bg-sky-50 text-sky-700",
   "Lo dijo, pero depende de algo que todavía no ocurre, o el detalle está incompleto."],
  ["40 - 69", "bg-amber-50 text-amber-700",
   "Señales mixtas o indirectas. Lo insinuó sin comprometerse, o se contradijo."],
  ["< 40", "bg-red-50 text-red-700",
   "Señaló lo contrario, o el ítem exigiría un cambio material en su situación."],
  ["0", "bg-slate-100 text-slate-400",
   "Sin evidencia en el transcript. <b>Cero es «no se habló del tema», no «mal lead»</b> — 66 de los 230 reportes de producción traen los cuatro ítems en cero porque la llamada no tenía transcript usable, y promediarlos como ceros reales subestima todo."],
];

function modalBandas() {
  const filas = BANDAS.map(([rango, cls, txt]) => `<tr class="align-top">
      <td class="py-1.5 pr-3 whitespace-nowrap"><span class="px-1.5 py-0.5 rounded text-xs font-semibold ${cls}">${escape(rango)}</span></td>
      <td class="py-1.5 text-xs" style="color:var(--text-2)">${txt}</td>
    </tr>`).join("");
  return `<div data-show="$bandas" data-on:click="$bandas=false"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      style="background:color-mix(in oklab, var(--text-1) 45%, transparent)">
    <div data-on:click__stop class="w-full max-w-2xl max-h-[85vh] overflow-auto rounded-xl border p-5"
         style="background:var(--surface-1);border-color:var(--border-1)">
      <div class="flex items-baseline gap-3 mb-1">
        <h2 class="text-base font-semibold" style="color:var(--text-1)">Qué significa cada banda</h2>
        <button data-on:click="$bandas=false" class="ml-auto text-xs px-2 py-0.5 rounded border"
          style="color:var(--text-2);border-color:var(--border-1)">cerrar ✕</button>
      </div>
      <p class="text-[11px] mb-4" style="color:var(--text-3)">
        El color no es decoración: son los mismos cortes que las <b>anclas del prompt mejorado</b>, así que
        la leyenda ES la rúbrica. Existen para que el techo se vea — en producción el 60% de los puntajes
        no nulos cae en 90-100, y una tabla de números crudos esconde exactamente eso.
      </p>
      <table class="w-full border-collapse mb-4">${filas}</table>

      <div class="rounded-lg border p-3 mb-3" style="border-color:var(--border-1);background:var(--surface-2)">
        <p class="text-xs font-medium mb-1" style="color:var(--text-1)">La excepción: <code>need</code> en mejorado-2</p>
        <p class="text-[11px]" style="color:var(--text-2)">
          Esas anclas <b>no pueden fallar sobre <code>need</code></b>: agendar una llamada de ventas ya es decir
          explícitamente que quieres el resultado, así que todo lead las cumple y el ítem no informa nada
          (gemini le pone ≥90 a 17 de 18 leads). En <b>mejorado-2</b>, <code>need</code> usa un eje propio —
          <b>el costo de la inacción</b>, no la fuerza del deseo declarado: qué le cuesta el statu quo, si ya
          gastó dinero o tiempo intentando resolverlo, y si puede nombrar qué se rompe si nada cambia.
          Querer el resultado vale <b>cero puntos</b> por sí solo, y la franja 40-69 es «meta real sin costo de
          demora» por bien articulada que esté.
        </p>
      </div>

      <div class="rounded-lg border p-3" style="border-color:var(--border-1)">
        <p class="text-xs font-medium mb-1" style="color:var(--text-1)">Ojo con las filas de <span class="text-slate-500">producción</span></p>
        <p class="text-[11px]" style="color:var(--text-2)">
          El prompt de producción <b>no declara ninguna ancla</b>: pide «Score/100» y nada más. Ahí el color
          describe lo que salió, no un criterio que se haya aplicado. Comparar una fila con rúbrica contra una
          sin rúbrica es justo lo que mide este cuadro.
        </p>
      </div>
    </div>
  </div>`;
}

function filaCelda(r, c, i) {
  const borde = i === 0 ? "border-t border-slate-200" : "";
  const nombre = `<td class="px-2 py-1 text-[11px] whitespace-nowrap ${CELDA_CLS[c.celda] || ""} ${borde}">
    ${escape(c.label)}${c.n_corridas > 1 ? `<span class="ml-1 text-[9px] text-slate-400">(${c.n_corridas} corridas)</span>` : ""}
  </td>`;
  if (!c.existe) return `<tr class="hover:bg-slate-50">${nombre}${faltante(r, c)}</tr>`;
  return `<tr class="hover:bg-slate-50">
    ${nombre}
    ${puntaje(c.budget)}${puntaje(c.authority)}${puntaje(c.need)}${puntaje(c.timeline)}
    <td class="px-1.5 py-1 text-center text-xs tabular-nums font-medium">${fmt(c.prom)}</td>
    ${deltaCell(r, c.celda)}
    <td class="px-2 py-1 text-[11px] max-w-56"><span class="line-clamp-1" title="${escape(c.arquetipo || "")}">${escape(c.arquetipo || "—")}</span></td>
    <td class="px-1.5 py-1 text-center text-[11px] tabular-nums" style="color:var(--text-2)">${c.prob == null ? "—" : fmt(c.prob)}</td>
    <td class="px-2 py-1 text-[10px] max-w-48" style="color:var(--text-3)"><span class="line-clamp-1" title="${escape(c.status || "")}">${escape(c.status || "—")}</span></td>
  </tr>`;
}

function grupo(r) {
  // Filtros client-side sobre las filas ya traídas: un cambio de filtro no
  // re-consulta (regla de viz/CLAUDE.md).
  const show = `($f=='' || ($f=='pend' && ${r.faltan ? "true" : "false"}) ` +
    `|| ($f=='ok' && ${r.faltan ? "false" : "true"}) ` +
    `|| ($f=='muestra' && ${r.en_muestra ? "true" : "false"}))`;
  // El rowspan sale de r.celdas.length, no de una constante: el cuadro creció
  // de 3 a 4 celdas y un número escrito a mano desalinea la tabla entera.
  const cab = `<td rowspan="${r.celdas.length}" class="px-2 py-1.5 align-top border-t border-slate-200 w-56 max-w-56"
      style="background:var(--surface-2)">
      <div class="flex items-baseline gap-1.5">
        <code class="text-[10px]" style="color:var(--text-3)">${escape(r.id8)}</code>
        ${r.orden ? `<span class="text-[9px] px-1 rounded" style="background:var(--surface-3);color:var(--text-3)">#${r.orden}</span>` : `<span class="text-[9px] italic" style="color:var(--text-3)">piloto</span>`}
      </div>
      <p class="text-xs font-medium break-words" style="color:var(--text-1)">${escape(r.lead || "—")}</p>
      <p class="text-[10px]" style="color:var(--text-3)">${escape(r.fecha || "")} · ${escape(r.closer && r.closer !== "—" ? r.closer : "closer sin resolver")}</p>
      <p class="text-[10px] line-clamp-2" style="color:var(--text-3)" title="${escape(r.programa || "")}">${escape(r.programa || "")}</p>
      ${r.buffer ? `<span class="text-[9px] text-amber-600" title="transcript guardado como Buffer serializado — se decodifica al leer">⚠ buffer</span>` : ""}
    </td>`;
  const filas = r.celdas.map((c, i) => filaCelda(r, c, i));
  // La celda del lead cuelga de la PRIMERA fila del grupo; las demás no la
  // repiten o la tabla se desalinea.
  filas[0] = filas[0].replace("<tr class=", `<tr data-grp="${escape(r.id8)}" class=`);
  return `<tbody data-show="${show}" class="border-b-2 border-slate-100">
    ${filas[0].replace(">", ">" + cab)}
    ${filas.slice(1).join("")}
  </tbody>`;
}

function filtro(val, label) {
  return `<button data-on:click="$f='${val}'"
    data-class="{'bg-indigo-600 text-white border-indigo-600': $f=='${val}', 'border-slate-200 hover:bg-slate-50': $f!='${val}'}"
    class="text-[11px] px-2 py-0.5 rounded-full border" style="color:inherit">${escape(label)}</button>`;
}

function renderComparativo(ui) {
  let filas = [];
  let fail = null;
  try {
    filas = fetchSource(ui.source, ui.params || {}).rows || [];
  } catch (e) {
    fail = e.message;
  }
  if (fail) {
    return `<section id="pane" class="flex-1 p-6">
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(fail)}</div>
    </section>`;
  }
  const tot = filas.length;
  const pend = filas.filter((r) => r.faltan).length;
  const huecos = filas.reduce((a, r) => a + r.faltan, 0);

  // Promedio por celda, con su n a la vista. Dos filas no son un hallazgo: el
  // n va pegado al número precisamente para que nadie lo lea sin él.
  const proms = ["produccion-gemini", "produccion-claude", "mejorado-claude", "mejorado2-claude"].map((k) => {
    const vs = filas.map((r) => (r.celdas.find((c) => c.celda === k) || {}).prom).filter((v) => v != null);
    const label = (filas[0]?.celdas.find((c) => c.celda === k) || {}).label || k;
    return { k, label, n: vs.length, prom: vs.length ? vs.reduce((a, b) => a + b, 0) / vs.length : null };
  });

  const kpis = proms.map((p) => `<div class="rounded-lg border border-slate-200 p-3" style="background:var(--surface-1)">
      <p class="text-[10px] uppercase tracking-wide ${CELDA_CLS[p.k] || ""}">${escape(p.label)}</p>
      <p class="text-2xl font-semibold tabular-nums" style="color:var(--text-1)">${p.prom == null ? "—" : p.prom.toFixed(1)}</p>
      <p class="text-[10px]" style="color:var(--text-3)">BANT promedio · n=${p.n}</p>
    </div>`).join("");

  // Copiar de una todos los handles pendientes: el uso real es por lotes.
  const cmds = filas.flatMap((r) => r.celdas.filter((c) => !c.existe && c.handle).map((c) => c.handle));
  const copiarTodos = cmds.length
    ? `<button data-on:click="navigator.clipboard.writeText(${JSON.stringify(cmds.join("\n")).replace(/"/g, "&quot;")});$copiado='todos'"
        class="text-[11px] px-2 py-0.5 rounded-md border border-indigo-300 text-indigo-600 hover:bg-indigo-50">
        copiar los ${cmds.length} pendientes</button>
       <span data-show="$copiado=='todos'" class="text-[10px] text-emerald-600">✓ copiado</span>`
    : `<span class="text-[11px] text-emerald-600">cuadro completo</span>`;

  return `<section id="pane" class="flex-1 p-6 overflow-hidden flex flex-col" data-signals="{f:'',copiado:'',bandas:false}">
    <header class="mb-1 flex items-baseline gap-3">
      <h1 class="text-xl font-semibold" style="color:var(--text-1)">${escape(ui.name)}</h1>
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
    </header>
    <p class="mb-3 text-xs" style="color:var(--text-3)">
      Cada lead se parte en cuatro: el reporte que produce hoy <b>gemini-2.5-flash</b> con el prompt de producción,
      el mismo prompt corrido por <b>claude</b>, el prompt <b>mejorado</b> (rúbrica de anclaje + lista cerrada de arquetipos)
      y <b>mejorado-2</b>, que le da a <code>need</code> un eje propio (costo de la inacción) porque la rúbrica genérica no lo movió.
      Cada delta compara contra su antecesor inmediato, de modo que aísle un solo cambio: fila 2−1 mide el <b>modelo</b>,
      3−2 mide la <b>rúbrica</b>, 4−3 mide el <b>eje de need</b>.
    </p>

    <div class="grid gap-3 mb-3" style="grid-template-columns:repeat(auto-fit,minmax(12rem,1fr))">${kpis}</div>

    <div class="mb-2 flex flex-wrap items-center gap-1.5 text-xs" style="color:var(--text-2)">
      ${filtro("", "todas")}
      ${filtro("muestra", "solo la muestra")}
      ${filtro("pend", `con huecos (${pend})`)}
      ${filtro("ok", "completas")}
      <span class="mx-1" style="color:var(--text-3)">·</span>
      <span><b>${tot}</b> llamadas · <b>${huecos}</b> celdas por correr</span>
      <span class="ml-auto flex items-center gap-2">${copiarTodos}</span>
    </div>

    <div class="flex-1 min-h-0 overflow-auto rounded-lg border border-slate-200" style="background:var(--surface-1)">
      <table class="w-full text-left border-collapse">
        <thead class="sticky top-0 text-[10px] uppercase tracking-wide" style="background:var(--surface-2);color:var(--text-3)">
          <tr>
            <th class="px-2 py-2">lead</th>
            <th class="px-2 py-2">prompt · modelo</th>
            <th class="px-1.5 py-2 text-center" title="Budget">B</th>
            <th class="px-1.5 py-2 text-center" title="Authority">A</th>
            <th class="px-1.5 py-2 text-center" title="Need">N</th>
            <th class="px-1.5 py-2 text-center" title="Timeline">T</th>
            <th class="px-1.5 py-2 text-center">prom</th>
            <th class="px-1.5 py-2 text-center" title="mejorado − producción">Δ</th>
            <th class="px-2 py-2">arquetipo</th>
            <th class="px-1.5 py-2 text-center" title="probabilidad de cierre">prob</th>
            <th class="px-2 py-2">resultado</th>
          </tr>
        </thead>
        ${filas.map(grupo).join("")}
      </table>
    </div>

    <p class="mt-3 text-[11px]" style="color:var(--text-3)">
      <button data-on:click="$bandas=true" class="group text-left" title="Ver qué significa cada banda">
        <span class="underline decoration-dotted underline-offset-2">Bandas</span>:
        <span class="px-1 rounded bg-emerald-100 text-emerald-800">≥90</span>
        <span class="px-1 rounded bg-sky-50 text-sky-700">70-89</span>
        <span class="px-1 rounded bg-amber-50 text-amber-700">40-69</span>
        <span class="px-1 rounded bg-red-50 text-red-700">&lt;40</span>
        <span class="px-1 rounded bg-slate-100 text-slate-400">0</span>
        <span class="ml-1 text-indigo-600 group-hover:underline">¿qué significan? →</span>
      </button>
      El botón <b>no genera</b> el reporte: copia el handle para dictarlo en la conversación — generarlo es una corrida de LLM, no un script.
      Cuando las dos variantes se corren en la misma sesión la segunda queda anclada en la primera, así que <b>Δ es un piso del efecto, no una medida</b>.
      Fuente: <code>bash/calls/comparativo_bant.sh</code>.
    </p>

    ${modalBandas()}
  </section>`;
}

module.exports = {
  id: "bant-comparativo",
  manifest: { consumes: "rows", overridable: ["pendientes", "muestra"] },
  render: renderComparativo,
};
