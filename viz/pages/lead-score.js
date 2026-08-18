// lead-score page — EL MODELO de score de leads, desde el único objeto que
// emite bash/calls/lead_score_model.sh.
//
// Es el entregable de la tarea 767605d8 (arquetipo A6.8): el output de esa
// tarea está tipado `web_url` y bindeado a esta URL, así que lo que se ve aquí
// ES la evidencia del contrato. Por eso la fuente no se cachea y por eso la
// página abre declarando qué población excluye — el criterio de aceptación lo
// exige explícitamente, y un tablero que esconde su denominador no lo cumple.
//
// La página está partida en DOS momentos, no en dos métricas, porque ese es el
// hallazgo del modelo: el score pre-llamada existe antes de asignar y puede
// ordenar la cola; el post-llamada existe después y solo puede ordenar el
// seguimiento. Presentarlos juntos como «el score» fue el error original.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };

function num(v) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  return Number.isNaN(n) ? escape(String(v)) : n.toLocaleString("es-CO");
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

// Tabla con una columna de porcentaje que se pinta como barra: la conversión
// por tramo es el corazón del criterio de aceptación («los tramos discriminan
// entre sí»), y una barra lo prueba de un vistazo mejor que cuatro decimales.
function tbl(headers, rows, { empty = "Sin datos.", barCol = null, barMax = 100 } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows
    .map((cells) =>
      `<tr>${cells
        .map((c, i) => {
          if (barCol !== null && i === barCol) {
            const pct = Number(c) || 0;
            const w = Math.max(1, Math.min(100, (pct / barMax) * 100));
            return `<td class="whitespace-nowrap"><div class="flex items-center gap-2">
              <span class="tabular-nums font-semibold" style="min-width:3.2rem;color:${pct >= 20 ? TONE.pos : pct > 0 ? TONE.cau : TONE.muted}">${pct.toFixed(1)}%</span>
              <span style="display:block;height:6px;border-radius:3px;width:${w}%;min-width:2px;background:${pct >= 20 ? "var(--pos-solid)" : "var(--cau-solid)"}"></span>
            </div></td>`;
          }
          return `<td class="align-top">${c}</td>`;
        })
        .join("")}</tr>`
    )
    .join("");
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`;
}

function renderLeadScore(ui) {
  // una fuente `emits: "object"` igual vuelve envuelta: fetchSource siempre
  // devuelve {rows}, con el objeto como su única fila (ver pages/ontology.js).
  const { rows } = fetchSource(ui.source || "lead_score", ui.params || {});
  const d = rows[0] || {};
  const m = d.meta || {};
  const tramos = d.tramos || [];
  const rasgos = d.rasgos || [];
  const alto = tramos.find((t) => t.tramo === "81-100") || {};

    const cabecera = `
      ${kpi("Llamadas con BANT", num(m.con_bant), { tone: "brand", sub: `de ${num(m.reportes)} reportes`, title: "El denominador honesto: reportes con calificación real" })}
      ${kpi("Conversión tramo alto", (alto.conv_pct ?? 0) + "%", { tone: "pos", sub: `BANT ≥ ${m.corte_util ?? 80}`, title: "Lo que convierte el tramo 81-100" })}
      ${kpi("Cola sin trabajar", num(d.cola_total), { tone: "neg", sub: "BANT alto, nunca cerró", title: "Llamadas de BANT ≥ 81 que quedaron en seguimiento" })}
      ${kpi("Contactos con encuesta", num(m.con_encuesta), { tone: "brand", sub: "score pre-llamada", title: "Contactos que respondieron la encuesta de agendamiento" })}`;

    // El criterio de aceptación exige declarar la población excluida. Va
    // arriba, no en una nota al pie: un tablero que la esconde no lo cumple.
    const exclusion = `<div class="alert mt-6" style="border-left:3px solid var(--cau-solid)">
      <p class="text-sm"><strong>${num(m.bant_cero)} reportes quedan fuera</strong> — traen los cuatro scores BANT en cero
      literal. No son leads malos: son llamadas sin transcript utilizable. Contarlos como ceros
      fabrica un tramo bajo que no existe y hunde todo promedio.</p>
    </div>`;

    const tTramos = tbl(
      ["Tramo BANT", "Llamadas", "Convirtió", "Conversión", "En seguimiento"],
      tramos.map((t) => [
        `<span class="font-semibold tabular-nums">${escape(t.tramo)}</span>`,
        `<span class="tabular-nums">${num(t.llamadas)}</span>`,
        `<span class="tabular-nums">${num(t.convirtio)}</span>`,
        t.conv_pct,
        `<span class="tabular-nums">${num(t.en_seguimiento)}</span>`,
      ]),
      { barCol: 3, barMax: 40 }
    );

    const tRasgos = tbl(
      ["Rasgo", "Llamadas", "BANT prom.", "Convirtió", "Conversión"],
      rasgos.map((r) => [
        escape(r.rasgo),
        `<span class="tabular-nums">${num(r.llamadas)}</span>`,
        `<span class="tabular-nums">${num(r.bant_prom)}</span>`,
        `<span class="tabular-nums">${num(r.convirtio)}</span>`,
        r.conv_pct,
      ]),
      { barCol: 4, barMax: 40 }
    );

    const encuesta = (rows, label) =>
      tbl(
        [label, "Leads", "Ganados", "Cierre"],
        (rows || []).map((r) => [
          `<span class="text-sm">${escape(String(r.respuesta || "").slice(0, 90))}</span>`,
          `<span class="tabular-nums">${num(r.leads)}</span>`,
          `<span class="tabular-nums">${num(r.ganados)}</span>`,
          r.cierre_pct,
        ]),
        { barCol: 3, barMax: 30 }
      );

    const tCola = tbl(
      ["Closer", "Leads sin trabajar"],
      (d.cola || []).map((c) => [escape(c.closer), `<span class="tabular-nums font-semibold">${num(c.n)}</span>`]),
      { empty: "La cola está vacía." }
    );

    // OJO: `id="pane"` NO es decorativo. El servidor parchea por SSE en modo
    // `outer` sin selector, así que Datastar busca el destino por id: una raíz
    // sin él no encuentra target (PatchElementsNoTargetsFound), el parche se
    // descarta en silencio y el visor se queda en la UI anterior mostrando el
    // overlay de carga. Toda página raiza en <section id="pane">.
    return `<section id="pane" class="flex-1 p-6 overflow-auto">
    <div class="max-w-6xl mx-auto">
      <div class="flex items-baseline gap-3 flex-wrap">
        <h1 class="text-xl font-bold" style="color:var(--text-1)">Modelo de score de leads</h1>
        <span class="badge badge-neutral">corte ${escape(d.corte || "—")}</span>
      </div>
      <p class="mt-1 text-sm" style="color:var(--text-3)">
        Entregable de la tarea <code>767605d8</code>. El argumento completo está en
        <code>docs/lead-score.md</code>; esto es su contraparte consultable.
      </p>

      <div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">${cabecera}</div>
      ${exclusion}

      ${section("Score POST-llamada · BANT", "existe después de la llamada — ordena el seguimiento, no la asignación")}
      ${tTramos}
      <p class="mt-2 text-xs" style="color:var(--text-3)">El corte útil está en 80, no en la mitad: entre 61 y 80 la conversión ya es casi cero. No es una escala lineal de calidad, es un umbral.</p>

      ${section("Los subgrupos", "cuatro rasgos base, normalizados desde 43 etiquetas de texto libre")}
      ${tRasgos}

      ${section("Score PRE-llamada · encuesta de agendamiento", "existe antes de asignar — es el único que puede ordenar la cola")}
      <div class="grid gap-4" style="grid-template-columns:repeat(auto-fit,minmax(20rem,1fr))">
        <div>${encuesta(d.presupuesto, "Presupuesto declarado")}</div>
        <div>${encuesta(d.disposicion, "Disposición declarada")}</div>
      </div>
      <p class="mt-2 text-xs" style="color:var(--text-3)">
        Discrimina, pero todavía no da un 0-100 defendible: los tramos altos de presupuesto tienen entre 12 y 23 leads,
        y con esas muestras la diferencia entre 16.7% y 26.7% es ruido. «Sin responder» nunca se pondera —
        rinde 7.7% en una pregunta y 12.3% en la otra, así que son poblaciones distintas, no un mismo grupo.
      </p>

      ${section("La cola accionable", `${num(d.cola_total)} llamadas de BANT ≥ 81 que quedaron en seguimiento y nunca cerraron`)}
      ${tCola}
      <p class="mt-2 text-xs" style="color:var(--text-3)">Es el tramo que convierte ${(alto.conv_pct ?? 0)}%. No necesita que se firme ninguna política: la lista existe.</p>

      <p class="mt-10 text-xs" style="color:var(--text-3)">
        Fuente: <code>bash/calls/lead_score_model.sh</code>. Normalizaciones y fuente de verdad:
        <code>bash/calls/lead_profile.sh</code>.
      </p>
    </div>
    </section>`;
}

module.exports = {
  id: "lead-score",
  manifest: { consumes: "object", overridable: ["project"] },
  render: renderLeadScore,
};
