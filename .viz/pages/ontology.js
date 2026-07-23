// ontology page — health and findings of the ontology itself, from the single
// object emitted by bash/graph/ontology_stats.sh.
//
// The source reads the BUILT graph artifacts, so this dashboard refreshes by
// rebuilding the graph (dump → build); no extra wiring. What it must never do
// is look fresh when it is not, hence the frescura bar: build timestamps plus
// drift (entities in the DB now vs entities the graph models).
//
// Two families of metric, kept visually apart because they answer different
// questions: the CONCEPT layer says what the organization is doing, the GRAPH
// HEALTH block says whether the knowledge base describing it is sound.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const TONE = {
  ok: { chip: "bg-emerald-100 text-emerald-800", val: "text-emerald-700", bar: "bg-emerald-500" },
  warn: { chip: "bg-amber-100 text-amber-800", val: "text-amber-700", bar: "bg-amber-500" },
  crit: { chip: "bg-rose-100 text-rose-800", val: "text-rose-700", bar: "bg-rose-500" },
  none: { chip: "bg-slate-100 text-slate-600", val: "text-slate-800", bar: "bg-indigo-500" },
};

function num(v) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  return Number.isNaN(n) ? escape(v) : n.toLocaleString("es-CO");
}

function card(label, value, { tone = "none", sub = "", title = "" } = {}) {
  const t = TONE[tone] || TONE.none;
  return `<div class="bg-white rounded-xl border border-slate-200 shadow-sm px-4 py-3"${
    title ? ` title="${escape(title)}"` : ""
  }>
    <p class="text-[11px] font-semibold uppercase tracking-wide text-slate-500">${escape(label)}</p>
    <p class="mt-0.5 text-2xl font-bold ${t.val} tabular-nums">${value}</p>
    ${sub ? `<p class="mt-0.5 text-[11px] text-slate-500">${sub}</p>` : ""}
  </div>`;
}

function sectionTitle(t, hint) {
  return `<div class="flex items-baseline gap-3 mt-8 mb-3">
    <h2 class="text-sm font-bold uppercase tracking-wider text-slate-700">${escape(t)}</h2>
    ${hint ? `<span class="text-xs text-slate-500">${escape(hint)}</span>` : ""}
  </div>`;
}

function tbl(headers, rows, empty) {
  if (!rows.length)
    return `<p class="text-sm text-slate-400 italic px-1 py-2">${escape(empty)}</p>`;
  return `<div class="overflow-x-auto bg-white rounded-xl border border-slate-200 shadow-sm">
    <table class="min-w-full text-sm">
      <thead><tr class="bg-slate-50 border-b border-slate-200">${headers
        .map(
          (h) =>
            `<th class="text-left font-semibold text-slate-600 text-xs uppercase tracking-wide px-3 py-2 ${
              h.right ? "text-right" : ""
            }">${escape(h.label)}</th>`
        )
        .join("")}</tr></thead>
      <tbody>${rows.join("")}</tbody>
    </table></div>`;
}

function renderOntology(ui) {
  // an `emits: "object"` source still comes back wrapped: fetchSource always
  // returns {rows}, with the object as its single row
  const { rows } = fetchSource(ui.source || "ontologia", ui.params || {});
  const d = rows[0] || {};
  const f = d.frescura || {};
  const dato = d.dato || {};
  const neg = d.negocio || {};
  const h = d.hallazgos || {};

  // ---- frescura + drift ----
  const drift = f.deriva_entidades;
  const driftTone = drift == null ? "none" : drift === 0 ? "ok" : "warn";
  const driftTxt =
    drift == null
      ? "sin verificar (DB no consultada)"
      : drift === 0
        ? `al día — la DB y el grafo coinciden en ${num(f.entidades_en_db)} entidades`
        : `${drift > 0 ? `+${drift}` : drift} entidad${Math.abs(drift) === 1 ? "" : "es"} en la DB que el grafo no modela`;
  const head = `<div class="mb-1">
    <h1 class="text-xl font-bold text-slate-800">Ontología de Ikigai</h1>
    <p class="text-sm text-slate-500">Salud del grafo de conocimiento y hallazgos de la capa conceptual.</p>
  </div>
  <div class="flex flex-wrap items-center gap-2 mt-3 mb-5">
    <span class="text-xs px-2 py-1 rounded-md ${TONE[driftTone].chip} font-medium">${escape(driftTxt)}</span>
    <span class="text-xs text-slate-500">grafo de dato <b>${escape(String(f.grafo_dato || "—")).slice(0, 16).replace("T", " ")}</b></span>
    <span class="text-xs text-slate-500">· negocio <b>${escape(String(f.grafo_negocio || "—")).slice(0, 16).replace("T", " ")}</b></span>
    <span class="text-xs text-slate-400">· se actualiza al reconstruir el grafo</span>
  </div>`;

  // ---- concept layer ----
  const fuera = Number(neg.pct_tareas_fuera_de_lo_declarado) || 0;
  const inst = Number(neg.pct_instanciado) || 0;
  const conc = Number(neg.concentracion_top1) || 0;
  const conceptCards = [
    card("Arquetipos instanciados", `${inst}%`, {
      tone: inst < 80 ? "warn" : "ok",
      sub: `${num(neg.arquetipos_usados)} de ${num(neg.arquetipos)} · ${num(neg.arquetipos_sin_usar)} nunca usados`,
      title: "Arquetipos del catálogo que al menos una tarea real instancia",
    }),
    card("Ejecución fuera de lo declarado", `${fuera}%`, {
      tone: fuera > 30 ? "crit" : fuera > 15 ? "warn" : "ok",
      sub: `${num(neg.pares_fuera_de_lo_declarado)} pares rol×arquetipo`,
      title: "% de asignaciones observadas donde el rol que ejecuta no es dueño declarado del SOP",
    }),
    card("Concentración del trabajo", `${conc}%`, {
      tone: conc > 20 ? "warn" : "none",
      sub: `top-5 acumula ${neg.concentracion_top5 || 0}%`,
      title: "Share de tareas del arquetipo más instanciado",
    }),
    card("Tareas etiquetadas", num(neg.tareas), {
      sub: `${num(neg.macro_procesos)} macro · ${num(neg.sops)} SOPs · ${num(neg.arquetipos)} arquetipos`,
    }),
    card("Contratos de trabajo", `${neg.pct_con_entregables || 0}%`, {
      tone: (Number(neg.pct_con_entregables) || 0) < 80 ? "warn" : "ok",
      sub: `arquetipos con entregable declarado · ${neg.pct_con_insumos || 0}% con insumos`,
      title: "Arquetipos que declaran su contrato de I/O (plantilla de tarea)",
    }),
    card("Conceptos", num(neg.conceptos), {
      sub: `${num(neg.relaciones)} relaciones · ${num(neg.roles)} roles · ${num(neg.clientes)} clientes`,
    }),
  ].join("");

  // ---- graph health ----
  const comps = Number(dato.componentes) || 0;
  const aisl = Number(dato.aisladas) || 0;
  const healthCards = [
    card("Entidades", num(dato.entidades), {
      sub: `${num(dato.relaciones)} relaciones · ${num(dato.reglas)} reglas`,
    }),
    card("Componentes conexos", num(dato.componentes), {
      tone: comps > 1 ? "warn" : "ok",
      sub: `mayor: ${num(dato.mayor_componente)} entidades (${dato.pct_en_mayor || 0}%)`,
      title: "Un grafo fragmentado en islas es peor que uno denso; los conteos solos no lo muestran",
    }),
    card("Entidades aisladas", num(dato.aisladas), {
      tone: aisl > 0 ? "warn" : "ok",
      sub: `${dato.pct_conectadas || 0}% tiene al menos una relación`,
      title: "Entidades sin ninguna relación: candidatas a modelar o a dar de baja",
    }),
    card("Grado medio", num(dato.grado_medio), {
      sub: `densidad ${dato.densidad ?? "—"}`,
    }),
    card("Resolución de implícitas", dato.resolucion_media == null ? "—" : `${dato.resolucion_media}%`, {
      tone: (Number(dato.resolucion_media) || 0) < 95 ? "warn" : "ok",
      sub: `${num(dato.implicitas)} verificadas · ${num(dato.implicitas_al_100)} al 100%`,
      title: "Promedio de la tasa con que resuelven las relaciones que ningún FK obliga",
    }),
    card("Cobertura de reglas", `${dato.pct_con_reglas || 0}%`, {
      sub: `${dato.pct_con_pk || 0}% con PK · ${num(dato.jsonb_con_relacion)}/${num(dato.jsonb_columnas)} jsonb con relación`,
      title: "Entidades con al menos un enum, CHECK o constraint UNIQUE",
    }),
  ].join("");

  // ---- value chain ----
  const maxT = Math.max(1, ...(h.cadena || []).map((c) => Number(c.tareas) || 0));
  const chainRows = (h.cadena || []).map((c) => {
    const t = Number(c.tareas) || 0;
    const w = Math.round((t / maxT) * 100);
    return `<tr class="border-b border-slate-100 last:border-0 hover:bg-slate-50">
      <td class="px-3 py-1.5 text-slate-400 tabular-nums text-xs">${c.orden ?? "—"}</td>
      <td class="px-3 py-1.5 font-mono text-xs text-indigo-600">${escape(c.macro)}</td>
      <td class="px-3 py-1.5 text-slate-700">${escape(c.nombre)}</td>
      <td class="px-3 py-1.5 text-right tabular-nums text-slate-500 text-xs">${num(c.arquetipos)}</td>
      <td class="px-3 py-1.5 text-right tabular-nums text-slate-700">${num(c.tareas)}</td>
      <td class="px-3 py-1.5 w-40">
        <div class="flex items-center gap-2">
          <div class="flex-1 h-1.5 bg-slate-100 rounded-full overflow-hidden">
            <div class="h-full ${t / maxT > 0.5 ? "bg-amber-500" : "bg-indigo-400"} rounded-full" style="width:${w}%"></div>
          </div>
          <span class="text-[11px] tabular-nums text-slate-500 w-10 text-right">${c.pct_tareas}%</span>
        </div></td>
    </tr>`;
  });

  const gapRows = (h.deriva_roles || []).map(
    (x) => `<tr class="border-b border-slate-100 last:border-0 hover:bg-slate-50">
      <td class="px-3 py-1.5 font-medium text-slate-700">${escape(x.rol)}</td>
      <td class="px-3 py-1.5 font-mono text-xs text-indigo-600">${escape(x.arquetipo)}</td>
      <td class="px-3 py-1.5 text-right tabular-nums text-slate-700">${num(x.tareas)}</td>
      <td class="px-3 py-1.5 text-xs text-slate-500">${escape(x.declarado)}</td>
    </tr>`
  );

  const fragRows = (h.implicitas_fragiles || []).map((x) => {
    const p = Number(x.pct) || 0;
    return `<tr class="border-b border-slate-100 last:border-0 hover:bg-slate-50">
      <td class="px-3 py-1.5 font-mono text-xs text-slate-700">${escape(x.relacion)}</td>
      <td class="px-3 py-1.5 text-right tabular-nums text-xs text-slate-500">${escape(x.detalle)}</td>
      <td class="px-3 py-1.5 text-right tabular-nums font-semibold ${
        p < 60 ? "text-rose-700" : p < 90 ? "text-amber-700" : "text-slate-700"
      }">${p}%</td>
    </tr>`;
  });

  const topRows = (h.top_arquetipos || []).map(
    (x) => `<tr class="border-b border-slate-100 last:border-0 hover:bg-slate-50">
      <td class="px-3 py-1.5 font-mono text-xs text-indigo-600">${escape(x.arquetipo)}</td>
      <td class="px-3 py-1.5 text-slate-700">${escape(x.nombre)}</td>
      <td class="px-3 py-1.5 text-right tabular-nums text-slate-700">${num(x.tareas)}</td>
      <td class="px-3 py-1.5 text-right tabular-nums text-slate-500 text-xs">${x.pct}%</td>
    </tr>`
  );

  const sinUsar = (h.sin_instanciar || [])
    .map(
      (a) =>
        `<span class="inline-block font-mono text-[11px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-600">${escape(a)}</span>`
    )
    .join(" ");

  const rechazadas = (h.rechazadas || [])
    .map(
      (r) => `<li class="px-3 py-2 border-b border-slate-100 last:border-0">
        <p class="font-mono text-xs text-rose-700">${escape(r.claim)}</p>
        <p class="text-xs text-slate-600 mt-0.5">${escape(r.why)}</p></li>`
    )
    .join("");

  const grid = (cards) =>
    `<div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">${cards}</div>`;

  return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">
    ${head}
    ${sectionTitle("Capa conceptual", "qué dice la ontología sobre cómo trabaja la organización")}
    ${grid(conceptCards)}
    ${sectionTitle("Salud del grafo de conocimiento", "si la base que describe todo eso es sólida")}
    ${grid(healthCards)}
    ${sectionTitle("Cadena de valor", "carga real de tareas por macro-proceso, en orden")}
    ${tbl(
      [
        { label: "#" },
        { label: "Macro" },
        { label: "Nombre" },
        { label: "Arq.", right: true },
        { label: "Tareas", right: true },
        { label: "Share" },
      ],
      chainRows,
      "Sin datos de cadena."
    )}
    ${sectionTitle("Ejecución fuera de lo declarado", `quién ejecuta lo que otro rol declara suyo (top ${(h.deriva_roles || []).length})`)}
    ${tbl(
      [{ label: "Rol que ejecuta" }, { label: "Arquetipo" }, { label: "Tareas", right: true }, { label: "Dueño declarado" }],
      gapRows,
      "Todo se ejecuta según lo declarado."
    )}
    ${sectionTitle("Arquetipos más instanciados", "dónde se va el trabajo de verdad")}
    ${tbl(
      [{ label: "Arquetipo" }, { label: "Actividad" }, { label: "Tareas", right: true }, { label: "Share", right: true }],
      topRows,
      "Sin tareas."
    )}
    ${sectionTitle("Relaciones implícitas por debajo del 100%", "la cola de higiene de datos")}
    ${tbl(
      [{ label: "Relación" }, { label: "Resuelve", right: true }, { label: "%", right: true }],
      fragRows,
      "Todas resuelven al 100%."
    )}
    ${
      sinUsar
        ? `${sectionTitle("Arquetipos nunca instanciados", `${(h.sin_instanciar || []).length} declarados que la operación aún no usa`)}
           <div class="bg-white rounded-xl border border-slate-200 shadow-sm p-3 leading-7">${sinUsar}</div>`
        : ""
    }
    ${
      rechazadas
        ? `${sectionTitle("Afirmaciones rechazadas", "relaciones que se creían reales y no resistieron verificación")}
           <ul class="bg-white rounded-xl border border-slate-200 shadow-sm">${rechazadas}</ul>`
        : ""
    }
    <p class="mt-8 text-xs text-slate-400">Fuente: <code>bash/graph/ontology_stats.sh</code> sobre
      <code>docs/graph/graph.json</code> + <code>business.json</code>. Reconstruir el grafo actualiza este tablero.</p>
  </section>`;
}

module.exports = {
  id: "ontology",
  manifest: { consumes: "object", overridable: [] },
  render: renderOntology,
};
