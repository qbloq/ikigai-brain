// desercion page — LA MEDICIÓN del impago y la deserción de cuotas, desde el
// único objeto que emite bash/finance/desercion.sh.
//
// Es el entregable de la tarea fb7a1c26 (arquetipo A12.8): el output de esa
// tarea está tipado `web_url` y bindeado a esta URL, así que lo que se ve aquí
// ES la evidencia del contrato. Por eso la fuente no se cachea, por eso la
// página abre declarando su ventana y su población excluida, y por eso la
// columna de madurez viaja pegada a la tasa de cobro en vez de vivir en una
// nota — el criterio de aceptación exige mostrar que sin ella la conclusión se
// invierte, y una tabla que la esconde no lo cumple.
//
// El orden es el del hallazgo, no el del dato: primero la curva por número de
// cuota (donde la deserción realmente ocurre), después el dinero con sus dos
// lecturas contradictorias, y de último el corte que todavía nadie firmó.

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

// Tabla con una columna pintada como barra. Aquí la barra mide COBRO, así que
// alto = bueno — al revés que en lead-score, donde medía conversión. El umbral
// de color se pasa explícito por eso.
function tbl(headers, rows, { empty = "Sin datos.", barCol = null, barMax = 100, barGood = 70 } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows
    .map((cells) =>
      `<tr>${cells
        .map((c, i) => {
          if (barCol !== null && i === barCol) {
            const pct = Number(c) || 0;
            const w = Math.max(1, Math.min(100, (pct / barMax) * 100));
            const good = pct >= barGood;
            return `<td class="whitespace-nowrap"><div class="flex items-center gap-2">
              <span class="tabular-nums font-semibold" style="min-width:3.2rem;color:${good ? TONE.pos : pct >= barGood / 2 ? TONE.cau : TONE.neg}">${pct.toFixed(1)}%</span>
              <span style="display:block;height:6px;border-radius:3px;width:${w}%;min-width:2px;background:${good ? "var(--pos-solid)" : pct >= barGood / 2 ? "var(--cau-solid)" : "var(--neg-solid)"}"></span>
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

function renderDesercion(ui) {
  // una fuente `emits: "object"` igual vuelve envuelta: fetchSource siempre
  // devuelve {rows}, con el objeto como su única fila (ver pages/ontology.js).
  const { rows } = fetchSource(ui.source || "desercion", ui.params || {});
  const d = rows[0] || {};
  const m = d.meta || {};
  const total = d.total || {};
  const curva = d.curva || [];
  const cohortes = d.cohortes || [];
  const excl = d.excluidos || {};

  const c1 = curva.find((c) => Number(c.cuota_n) === 1) || {};
  const c2 = curva.find((c) => Number(c.cuota_n) === 2) || {};

  // La comparación que prueba el criterio 1, calculada y no narrada. NO es
  // «la que mejor cobra contra la que peor cobra»: las cohortes viejas cobran
  // mejor de verdad, así que ese par sale con la madurez al revés y desmiente
  // el texto que lo acompaña. El artefacto vive en la cohorte MÁS JOVEN, que
  // se ve bien sólo porque casi todas sus cuotas son la primera.
  const conN = cohortes.filter((c) => Number(c.debidas) >= 30);
  const joven = conN.slice().sort((a, b) => Number(a.cuota_prom) - Number(b.cuota_prom))[0];
  const peor = conN.slice().sort((a, b) => Number(a.pct_cobrado) - Number(b.pct_cobrado))[0];
  // Sólo se muestra si el dato de verdad exhibe la inversión. Un callout que se
  // imprime siempre es una afirmación, no una medición.
  const inversion =
    joven && peor && joven.cohorte !== peor.cohorte &&
    Number(joven.pct_cobrado) > Number(peor.pct_cobrado) &&
    Number(joven.cuota_prom) < Number(peor.cuota_prom);

  const cabecera = `
    ${kpi("Vencido sin cobrar", usd(total.usd), { tone: "neg", sub: `${num(total.cuotas)} cuotas · ${num(total.planes)} planes`, title: "Todo lo vencido dentro de la ventana declarada, no solo el bucket >30d" })}
    ${kpi("Paga la cuota 1", (c1.pct_cobrado ?? 0) + "%", { tone: "pos", sub: `${num(c1.debidas)} cuotas debidas`, title: "Casi todos pagan la primera" })}
    ${kpi("Paga la cuota 2", (c2.pct_cobrado ?? 0) + "%", { tone: "neg", sub: `${num(c2.debidas)} cuotas debidas`, title: "Aquí se cae: ocurre después de entregar el primer mes" })}
    ${kpi("Ventana", escape(String(m.desde || "—")), { tone: "brand", sub: `hasta ${escape(String(m.corte || "—"))}`, title: "Declarada, no implícita: un total sin ventana no se puede comparar contra sí mismo" })}`;

  // Los dos criterios que exigen declarar denominador y exclusiones. Van
  // arriba: un tablero que los esconde no los cumple.
  const declaraciones = `
    <div class="alert mt-6" style="border-left:3px solid var(--cau-solid)">
      <p class="text-sm"><strong>Toda tasa se calcula sobre cuotas YA VENCIDAS.</strong>
      Una cuota que aún no vence no es impago, y contarla como tal hunde cualquier tasa.
      La curva y las cohortes usan toda la historia; el dinero vencido cuenta desde ${escape(String(m.desde || "—"))}.</p>
    </div>
    <div class="alert mt-3" style="border-left:3px solid var(--cau-solid)">
      <p class="text-sm"><strong>${num(excl.planes)} planes quedan fuera</strong>
      (${num(excl.cuotas)} cuotas, ${usd(excl.usd)}) — no tienen <code>project_id</code>, así que no se pueden
      atribuir a ningún proyecto. No entran a ningún número de esta página.</p>
    </div>`;

  const tCurva = tbl(
    ["Cuota nº", "Debidas", "Pagadas", "Cobrado", "Sin cobrar"],
    curva.map((c) => [
      `<span class="font-semibold tabular-nums">${escape(String(c.cuota_n))}</span>`,
      `<span class="tabular-nums">${num(c.debidas)}</span>`,
      `<span class="tabular-nums">${num(c.pagadas)}</span>`,
      c.pct_cobrado,
      `<span class="tabular-nums">${usd(c.sin_cobrar)}</span>`,
    ]),
    { barCol: 3, barMax: 100, barGood: 70 }
  );

  const tCohortes = tbl(
    ["Cohorte de venta", "Planes", "Debidas", "Cobrado", "Cuota prom.", "Sin cobrar"],
    cohortes.map((c) => [
      `<span class="font-semibold tabular-nums">${escape(String(c.cohorte))}</span>`,
      `<span class="tabular-nums">${num(c.planes)}</span>`,
      `<span class="tabular-nums">${num(c.debidas)}</span>`,
      c.pct_cobrado,
      `<span class="tabular-nums font-semibold" style="color:var(--text-2)">${num(c.cuota_prom)}</span>`,
      `<span class="tabular-nums">${usd(c.sin_cobrar)}</span>`,
    ]),
    { barCol: 3, barMax: 100, barGood: 70 }
  );

  const tVenc = tbl(
    ["Mes de vencimiento", "Cuotas", "Sin cobrar", "% del total"],
    (d.por_vencimiento || []).map((r) => [
      `<span class="tabular-nums">${escape(String(r.mes))}</span>`,
      `<span class="tabular-nums">${num(r.cuotas)}</span>`,
      `<span class="tabular-nums">${usd(r.usd)}</span>`,
      `<span class="tabular-nums">${num(r.pct)}%</span>`,
    ])
  );

  const tCoh = tbl(
    ["Cohorte de venta", "Planes", "Cuotas", "Sin cobrar", "% del total"],
    (d.por_cohorte || []).map((r) => [
      `<span class="tabular-nums">${escape(String(r.cohorte))}</span>`,
      `<span class="tabular-nums">${num(r.planes)}</span>`,
      `<span class="tabular-nums">${num(r.cuotas)}</span>`,
      `<span class="tabular-nums">${usd(r.usd)}</span>`,
      `<span class="tabular-nums">${num(r.pct)}%</span>`,
    ])
  );

  // El corte de E2. Sin decidir se muestra como hueco declarado, no se rellena
  // con un default: inventarlo aquí sería exactamente lo que el criterio
  // bc91d41d prohíbe.
  const a = d.arrastre;
  const arrastre = a
    ? `<div class="grid gap-4" style="grid-template-columns:repeat(auto-fit,minmax(16rem,1fr))">
        <div class="card card-pad">
          <p class="text-xs uppercase tracking-wider" style="color:var(--text-3)">Arrastre histórico</p>
          <p class="text-lg font-bold tabular-nums" style="color:var(--cau-text)">${usd(a.arrastre.usd)}</p>
          <p class="text-xs" style="color:var(--text-3)">${num(a.arrastre.planes)} planes · ${num(a.arrastre.cuotas)} cuotas · iniciados antes de ${escape(String(a.corte))}</p>
        </div>
        <div class="card card-pad">
          <p class="text-xs uppercase tracking-wider" style="color:var(--text-3)">Deterioro nuevo</p>
          <p class="text-lg font-bold tabular-nums" style="color:var(--neg-text)">${usd(a.nuevo.usd)}</p>
          <p class="text-xs" style="color:var(--text-3)">${num(a.nuevo.planes)} planes · ${num(a.nuevo.cuotas)} cuotas · desde ${escape(String(a.corte))}</p>
        </div>
      </div>`
    : `<div class="alert" style="border-left:3px solid var(--neg-solid)">
        <p class="text-sm"><strong>Sin decidir.</strong> El corte que separa arrastre histórico de deterioro nuevo
        es la entrada <code>E2</code> de la tarea: una decisión humana que no está en la base — ninguna columna
        distingue un impago por deterioro nuevo de uno arrastrado desde un cliente antiguo mal servido.
        Mientras no se firme, esta sección queda vacía a propósito. Ponerle un default sería fabricar la respuesta.</p>
        <p class="text-sm mt-2" style="color:var(--text-3)">Para simularlo:
        <code>bash/finance/desercion.sh --project "…" --corte YYYY-MM-DD</code></p>
      </div>`;

  // OJO: `id="pane"` NO es decorativo — ver la nota en pages/lead-score.js.
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
  <div class="max-w-6xl mx-auto">
    <div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">Impago y deserción de cuotas</h1>
      <span class="badge badge-neutral">${escape(String(m.proyecto || "—"))}</span>
      <span class="badge badge-neutral">corte ${escape(String(m.corte || "—"))}</span>
    </div>
    <p class="mt-1 text-sm" style="color:var(--text-3)">
      Entregable de la tarea <code>fb7a1c26</code> (arquetipo A12.8). Se recalcula contra datos vivos:
      no es una foto, es el instrumento.
    </p>

    <div class="grid gap-3 mt-5" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">${cabecera}</div>
    ${declaraciones}

    ${section("La curva de deserción", "por número de cuota — donde la deserción realmente ocurre")}
    ${tCurva}
    <p class="mt-2 text-xs" style="color:var(--text-3)">
      La deserción no está repartida, está concentrada en dónde va la cuota. Casi todos pagan la primera;
      la segunda la paga siete de cada diez. Eso ocurre <em>después</em> de entregar el primer mes:
      no es un problema de cobranza, es el cliente decidiendo que no sigue. Cada punto trae su n —
      un promedio único escondería exactamente esto.
    </p>

    ${section("Cohortes ajustadas por madurez", "la tasa de cobro por mes de venta, con hasta qué cuota alcanzó a llegar")}
    ${tCohortes}
    ${
      inversion
        ? `<div class="alert mt-3" style="border-left:3px solid var(--neg-solid)">
            <p class="text-sm"><strong>Sin la columna de madurez, esta tabla dice lo contrario de lo que pasa.</strong>
            La cohorte <code>${escape(String(joven.cohorte))}</code> aparece cobrando ${num(joven.pct_cobrado)}% contra
            ${num(peor.pct_cobrado)}% de <code>${escape(String(peor.cohorte))}</code>, lo que se lee como una recuperación.
            Es un espejismo: va en la cuota ${num(joven.cuota_prom)} en promedio y la otra en la ${num(peor.cuota_prom)},
            y la cuota 1 la paga el ${num(c1.pct_cobrado)}%. No cobra mejor: alcanzó a llegar menos lejos.</p>
            <p class="text-sm mt-2" style="color:var(--text-3)">Ojo con el reverso: las cohortes de 2025 sí cobran mejor
            <em>con</em> más madurez encima, y eso no es artefacto — es el deterioro real que la tarea vino a medir.</p>
          </div>`
        : ""
    }

    ${section("El dinero vencido, en sus dos lecturas", "dan respuestas opuestas, y por eso hace falta E2")}
    <div class="grid gap-4" style="grid-template-columns:repeat(auto-fit,minmax(20rem,1fr))">
      <div>
        <p class="text-xs font-semibold mb-2" style="color:var(--text-2)">1 · Por cuándo venció la cuota</p>
        ${tVenc}
      </div>
      <div>
        <p class="text-xs font-semibold mb-2" style="color:var(--text-2)">2 · Por cuándo se vendió el plan</p>
        ${tCoh}
      </div>
    </div>
    <p class="mt-2 text-xs" style="color:var(--text-3)">
      Una cuota vence tarde aunque el cliente sea viejo. Por eso la fecha de vencimiento —la que trae el reporte
      de cobranza, y la que uno mira por defecto— <strong>no puede separar arrastre de deterioro</strong>:
      hace ver reciente lo que se vendió hace medio año. La cohorte de venta sí distingue, pero tampoco decide
      sola: no dice si el cliente dejó de pagar porque la entrega falló o porque nunca iba a pagar.
    </p>

    ${section("Arrastre histórico vs deterioro nuevo", "la entrada E2 de la tarea")}
    ${arrastre}

    <p class="mt-10 text-xs" style="color:var(--text-3)">
      Fuente: <code>bash/finance/desercion.sh</code>. El total reconcilia con los buckets vencidos de
      <code>bash/finance/cobranza.sh --summary</code>. Insumo bindeado en la tarea:
      <code>bash/tasks/run_io_query.sh 69c30b3f</code>.
    </p>
  </div>
  </section>`;
}

module.exports = {
  id: "desercion",
  manifest: { consumes: "object", overridable: ["project", "desde", "corte"] },
  render: renderDesercion,
};
