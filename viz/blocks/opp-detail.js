// opp-detail block (#opp-detail) — panel de detalle para UNA oportunidad del
// CRM y su contacto, sobre la fuente `crm_opp_detail`.
//
// Existe por una razón concreta: cuando un lead no tiene dueño, la pregunta no
// es "quién es" sino "por dónde entró y qué dijo" — eso decide si se rescata y
// quién debería tomarlo. Por eso el panel pone arriba la atribución (tags +
// utm_*) y el survey de calificación que el lead ya respondió, en vez de
// enterrarlos bajo los campos del CRM.

const { fetchSource } = require("../lib/datasources");
const { escape, section } = require("../lib/kit");

// Ancho mayor que el panel de tareas: las respuestas del survey son párrafos,
// no etiquetas, y truncarlas destruye justo lo que hace útil al panel.
function panelShell(inner) {
  return `<div id="opp-detail" class="w-[34rem] h-full overflow-y-auto">${inner}</div>`;
}

function empty() {
  return panelShell(
    `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
      <p>Selecciona un lead para ver su ficha y lo que respondió.</p>
    </div>`
  );
}

function row(label, value, mono) {
  return `<div class="flex gap-2">
    <dt class="text-slate-400 w-28 shrink-0">${escape(label)}</dt>
    <dd class="text-slate-700 min-w-0 break-words${mono ? " font-mono text-xs" : ""}">${escape(value || "—")}</dd>
  </div>`;
}

function chips(v) {
  if (!v || v === "—") return '<span class="text-xs text-slate-400 italic">— sin tags</span>';
  return v
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean)
    .map((t) => `<span class="badge badge-neutral mr-1 mb-1 inline-block">${escape(t)}</span>`)
    .join("");
}

// Los campos de GHL mezclan dos cosas distintas: respuestas del lead y
// telemetría de atribución (utm_*, fbp, fbc, gclid). Separarlas es lo que
// convierte un volcado en información: arriba de dónde vino, abajo qué dijo.
const ATTR_RE = /^(utm_|fbp$|fbc$|gclid|referrer|source|medium|campaign)/i;

function fieldsBlocks(fields) {
  if (!Array.isArray(fields) || !fields.length) return "";
  const attr = fields.filter((f) => ATTR_RE.test(f.campo || ""));
  const survey = fields.filter((f) => !ATTR_RE.test(f.campo || ""));

  const attrHtml = attr.length
    ? section(
        "Atribución",
        attr.length,
        `<dl class="text-sm space-y-1">${attr
          .map((f) => row(f.campo, f.valor, true))
          .join("")}</dl>`
      )
    : "";

  const surveyHtml = survey.length
    ? section(
        "Lo que respondió",
        survey.length,
        `<ul class="space-y-3">${survey
          .map(
            (f) => `<li>
              <p class="text-xs text-slate-500 mb-0.5">${escape(f.campo)}</p>
              <p class="text-sm text-slate-700 break-words">${escape(f.valor)}</p>
            </li>`
          )
          .join("")}</ul>`
      )
    : "";

  return attrHtml + surveyHtml;
}

function renderOppDetail(id) {
  if (!id) return empty();
  let d;
  try {
    const res = fetchSource("crm_opp_detail", { id });
    d = Array.isArray(res.rows) ? res.rows[0] : res.rows;
  } catch (e) {
    return panelShell(`<div class="p-5"><div class="alert alert-neg">${escape(e.message)}</div></div>`);
  }
  if (!d || !d.id) return panelShell('<div class="p-5 text-sm text-slate-400">No se encontró la oportunidad.</div>');

  const sinDueno = d.dueno === "sin dueño";
  const header = `<div class="flex items-start gap-2 mb-1">
      <h2 class="text-base font-semibold text-slate-800 min-w-0 break-words">${escape(d.lead || "Lead")}</h2>
      <button class="ml-auto shrink-0 text-slate-400 hover:text-slate-600" data-on:click="$detailOpen=false" title="cerrar">✕</button>
    </div>
    <div class="flex flex-wrap items-center gap-2 mb-4">
      ${sinDueno ? '<span class="badge badge-neg">sin dueño</span>' : `<span class="badge badge-pos">${escape(d.dueno)}</span>`}
      <span class="badge badge-neutral">${escape(d.etapa || "—")}</span>
      <span class="text-xs text-slate-500">${escape(d.dias)} días</span>
      ${Number(d.llamadas) > 0 ? `<span class="badge badge-cau" title="llamadas agendadas por este contacto">${escape(d.llamadas)} llamada(s)</span>` : ""}
      ${Number(d.otras_opps) > 0 ? `<span class="badge badge-neutral" title="otras oportunidades del mismo contacto">+${escape(d.otras_opps)} opp</span>` : ""}
    </div>`;

  const ficha = section(
    "Oportunidad",
    null,
    `<dl class="text-sm space-y-1">
      ${row("Estado", d.estado)}
      ${row("Pipeline", d.pipeline)}
      ${row("Proyecto", d.proyecto)}
      ${row("Creada", d.creada)}
      ${row("Último cambio", d.ultimo_cambio)}
      ${d.valor ? row("Valor", d.valor) : ""}
      ${row("Id en GHL", d.ghl_id, true)}
    </dl>`
  );

  const contacto = section(
    "Contacto",
    null,
    `<dl class="text-sm space-y-1">
      ${row("Nombre", d.contacto)}
      ${row("Email", d.email, true)}
      ${row("Teléfono", d.telefono, true)}
      ${row("Id en GHL", d.contacto_ghl_id, true)}
      ${row("Ingerido", d.contacto_ingerido)}
    </dl>
    <div class="mt-2">${chips(d.tags)}</div>`
  );

  return panelShell(`<div class="p-5">${header}${ficha}${contacto}${fieldsBlocks(d.campos_personalizados)}</div>`);
}

module.exports = {
  id: "opp-detail",
  manifest: { slot: "detail", frag: "panel", width: "34rem", selSignal: "selectedOpp" },
  frags: { panel: (ctx) => renderOppDetail(ctx.params.get("id") || "") },
  renderOppDetail,
};
