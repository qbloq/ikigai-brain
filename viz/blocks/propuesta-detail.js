// propuesta-detail block — el DETALLE de la vista «Propuestas de reuniones»:
// el contrato completo de UNA propuesta (lo que la reunión propone crear) y
// las dos preguntas que un humano necesita para decidirla:
//   1. ¿esto está bien planteado?  → contrato, slots, evidencia, validación
//   2. ¿esto ya existe?            → «Relacionadas», en dos capas: las
//      hermanas del propio lote (sin tocar Postgres — lib/similitud) y las
//      tareas vivas del cerebro (`tareas_relacionadas`, con motivo y score).
//
// El único write es `propuesta_mark.sh`: la decisión es una MARCA en la sqlite
// local, igual que el Merge del cruce. Nada de esto toca Postgres — crear las
// tareas marcadas «entra» es trabajo de bash/tasks/crear_de_propuestas.sh,
// desde la conversación.
// Spec: docs/superpowers/specs/2026-08-24-revision-propuestas-design.md

const { fetchSource } = require("../lib/datasources");
const { escape, cell, section, dueFmt, priorityDot, jsStr } = require("../lib/kit");
const { tokens, jaccard } = require("../lib/similitud");
const { parseJson, decisionBadge, seccionBadge } = require("./propuestas-table");
const catalogo = require("../../catalog/sop-archetypes.json");

const MARK = "bash/localdb/propuesta_mark.sh";
const WIDTH = "34rem";

const ARQ = new Map((catalogo.archetypes || []).map((a) => [a.id, a]));

function shell(inner) {
  return `<div id="prop-detail" class="w-[34rem] h-full overflow-y-auto">${inner}</div>`;
}

function vacio(msg) {
  return shell(`<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
    <p>${escape(msg)}</p>
  </div>`);
}

function dt(label, value) {
  return `<div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">${escape(label)}</dt><dd class="text-slate-700 min-w-0">${value}</dd></div>`;
}

// El id corto es el handle que se dicta en la conversación; lo que copia es el
// uuid COMPLETO, que es lo que piden los scripts (patrón de pages/cruce.js).
function idCopiable(idFull, key) {
  const full = String(idFull || "");
  // `jsStr` y no `escape`: estos dos valores van DENTRO de literales JS, y
  // escape() no toca el apóstrofo (kit.js) — partiría la expresión.
  const jf = escape(jsStr(full));
  const jk = escape(jsStr(key));
  return `<button data-on:click="navigator.clipboard.writeText(${jf});$copiado=${jk}"
    class="font-mono text-[10px] text-slate-500 hover:text-indigo-600 inline-flex items-center gap-1"
    title="Clic para copiar el id completo">${escape(full.slice(0, 8))}<span aria-hidden="true">⧉</span></button>
    <span data-show="$copiado==${jk}" class="text-[10px] text-emerald-600">✓</span>`;
}

const ESTADO_BADGE = {
  pending: ["badge-neutral", "Pendiente"],
  in_progress: ["badge-cau", "En curso"],
  completed: ["badge-pos", "Hecha"],
  blocked: ["badge-neg", "Bloqueada"],
  cancelled: ["badge-neutral", "Cancelada"],
};
function estadoBadge(v) {
  const [c, t] = ESTADO_BADGE[v] || ["badge-neutral", v || "—"];
  return `<span class="badge ${c}" title="${escape(v || "")}">${escape(t)}</span>`;
}

// --- relacionadas, capa 1: el propio lote ----------------------------------
// Tres señales, todas locales (ninguna consulta a Postgres): las que esta
// propuesta declara depender (`depende_de` por `ref`), las que comparten
// arquetipo+proyecto, y las que se parecen por título (Jaccard ≥ 0.25 sobre
// los tokens de lib/similitud, la MISMA regla que usa relacionadas.sh).
function hermanas(row, todas) {
  const mismas = todas.filter((h) => h.meeting_id === row.meeting_id && String(h.n) !== String(row.n));
  const dep = new Set(parseJson(row.depende_de, []).map(String));
  const tk = tokens(row.titulo);
  const out = [];
  for (const h of mismas) {
    const motivos = [];
    if (dep.has(String(h.ref))) motivos.push("depende de ella");
    if (row.arquetipo && h.arquetipo === row.arquetipo && h.proyecto === row.proyecto) motivos.push("mismo arquetipo y proyecto");
    const j = jaccard(tk, tokens(h.titulo));
    if (j >= 0.25) motivos.push(`título ${j.toFixed(2)}`);
    if (motivos.length) out.push({ h, motivo: motivos.join(" · "), j });
  }
  return out.sort((a, b) => b.j - a.j);
}

function bloqueLote(row, todas) {
  const rel = hermanas(row, todas);
  if (!rel.length) return '<p class="text-xs text-slate-400 italic">— ninguna en este lote</p>';
  return `<ul class="space-y-1.5">${rel
    .map(
      ({ h, motivo }) => `<li class="flex items-start gap-2">
      <code class="text-[10px] text-slate-400 shrink-0 mt-0.5">${escape(h.ref || "")}</code>
      <div class="min-w-0">
        <p class="text-sm text-slate-700">${escape(h.titulo || "")}</p>
        <p class="text-[11px] text-slate-400">${escape(motivo)} · ${decisionBadge(h)}</p>
      </div>
    </li>`
    )
    .join("")}</ul>`;
}

// --- relacionadas, capa 2: el cerebro --------------------------------------
// Esta SÍ va a Postgres (~1s). Si falla, se dice: un panel que se queda mudo
// hace creer que no hay nada parecido, que es lo contrario de lo que pasó.
function bloqueCerebro(row) {
  const asignados = parseJson(row.asignados, []);
  const ids = parseJson(row.relacionadas, []);
  let rows = [];
  try {
    rows = fetchSource("tareas_relacionadas", {
      titulo: row.titulo || "",
      project: row.proyecto || "",
      archetype: row.arquetipo || "",
      assignee: asignados.join(","),
      ids: ids.join(","),
      limit: "10",
    }).rows;
  } catch (e) {
    return `<div class="alert alert-neg text-xs">${escape(e.message)}</div>`;
  }
  if (!rows.length) return '<p class="text-xs text-slate-400 italic">— nada parecido en el cerebro</p>';
  return `<ul class="space-y-1.5">${rows
    .map(
      (t) => `<li class="flex items-start gap-2">
      <span class="shrink-0 mt-0.5">${idCopiable(t.id_full || t.id, `rel${t.id}`)}</span>
      <div class="min-w-0">
        <p class="text-sm text-slate-700">${escape(t.title || "")}</p>
        <p class="text-[11px] text-slate-400">${estadoBadge(t.status)} ${escape(t.motivo || "")} · score ${Number(t.score || 0)}${t.archetype ? ` · ${escape(t.archetype)}` : ""}</p>
      </div>
    </li>`
    )
    .join("")}</ul>`;
}

// --- la decisión -----------------------------------------------------------
function bloqueDecision(row) {
  const n = String(row.n);
  if (row.creada_id) {
    return `<div class="flex items-center gap-2">
      <span class="badge badge-brand">✓ ya creada en el cerebro</span>
      ${idCopiable(row.creada_id, `creada${n}`)}
      <span class="text-[11px] text-slate-400">${escape(String(row.creada_en || "").slice(0, 16))}</span>
    </div>
    <p class="text-[11px] text-slate-400 mt-1">La propuesta quedó congelada: la decisión ya se ejecutó.</p>`;
  }
  // El nombre de la señal es un IDENTIFICADOR (no admite jsStr), así que se
  // reduce a dígitos; el mismo valor viaja por la URL como literal escapado.
  const sig = `_nota_${n.replace(/[^0-9]/g, "")}`;
  const post = (d) =>
    `@post('/c/propuesta-detail/act/mark?n='+encodeURIComponent(${escape(jsStr(n))})+'&d=${d}&nota='+encodeURIComponent($${sig}))`;
  const quitar = row.decision
    ? `<button class="btn btn-ghost btn-xs" data-on:click="${post("ninguna")}" data-indicator:loading
        title="Borrar la decisión y volver a pendiente">quitar</button>`
    : "";
  // `entra` es UN valor con DOS significados, y el rótulo tiene que decir cuál:
  // en §A el ejecutor crea la tarea; en §B nunca crea nada (spec §3) — la marca
  // dice «hay que resolverlo en conversación». Prometer creación en una §B
  // sería prometer algo que ningún script hará.
  const esB = row.seccion === "B";
  const rotulo = esB ? "Se resuelve" : "Entra";
  const tPrim = esB ? "Marcar: se resuelve en conversación" : "Marcar: se creará en el cerebro";
  const tSec = esB ? "Marcar: no hay nada que hacer" : "Marcar: no se crea";
  const ayuda = esB
    ? `<p class="text-[11px] text-slate-400 mt-1">§B: se resuelve en conversación (comentario, cierre, reasignación); no se crea tarea.</p>`
    : "";
  return `<input data-bind="${sig}" class="input input-sm mb-2" placeholder="nota (opcional)" />
    <div class="flex items-center gap-2">
      <button class="btn btn-primary btn-xs" data-on:click="${post("entra")}" data-indicator:loading
        title="${escape(tPrim)}">${escape(rotulo)}</button>
      <button class="btn btn-secondary btn-xs" data-on:click="${post("se_queda")}" data-indicator:loading
        title="${escape(tSec)}">Se queda</button>
      ${quitar}
      ${row.decidida_en ? `<span class="text-[11px] text-slate-400 ml-auto">${escape(String(row.decidida_en).slice(0, 16))}</span>` : ""}
    </div>
    ${ayuda}
    ${row.decision_nota ? `<p class="text-[11px] text-slate-500 mt-1">${escape(row.decision_nota)}</p>` : ""}`;
}

// --- el panel --------------------------------------------------------------
function panel(n, aviso) {
  if (!n) return vacio("Selecciona una propuesta para ver su contrato.");
  let todas = [];
  try {
    todas = fetchSource("propuestas").rows;
  } catch (e) {
    return shell(`<div class="p-5"><div class="alert alert-neg">${escape(e.message)}</div></div>`);
  }
  const row = todas.find((r) => String(r.n) === String(n));
  if (!row) return vacio(`Propuesta ${n} no encontrada (¿se recargó el lote?).`);

  const a = row.arquetipo ? ARQ.get(row.arquetipo) : null;
  const slots = parseJson(row.slots, {});
  const asignados = parseJson(row.asignados, []);
  // Una fila SIN contrato (todas las §B) no tiene vence, ni slots, ni cita: no
  // es que falten, es que esa fila no describe una tarea creable. Pintar
  // «Vence —», «sin slots» y «sin cita del transcript» sería ruido que se lee
  // como carencia. Se muestran solo los campos que de verdad traen algo.
  const conContrato = !!row.contrato;
  const slotsHtml = Object.keys(slots).length
    ? `<dl class="text-xs space-y-0.5">${Object.entries(slots)
        .map(
          ([k, v]) =>
            `<div class="flex gap-2"><dt class="text-slate-400 w-28 shrink-0">${escape(k)}</dt><dd class="text-slate-600 min-w-0 break-words">${escape(String(v))}</dd></div>`
        )
        .join("")}</dl>`
    : '<p class="text-xs text-slate-400 italic">— sin slots</p>';

  const banner = aviso ? `<div class="alert alert-neg mb-3">${escape(aviso)}</div>` : "";
  const invalida =
    row.valida === 0 || row.valida === "0"
      ? `<div class="alert alert-neg mb-3"><div class="a-body">Contrato inválido: ${escape(row.error_validacion || "sin detalle")}</div></div>`
      : "";
  const pregunta = row.pregunta
    ? `<div class="alert alert-cau mb-3"><div class="a-body">${escape(row.pregunta)}</div></div>
       ${row.accion_sugerida ? `<p class="text-xs text-slate-500 mb-3"><span class="text-slate-400">Acción sugerida:</span> ${escape(row.accion_sugerida)}</p>` : ""}`
    : "";

  const sigNota = `_nota_${String(n).replace(/[^0-9]/g, "")}`;
  const inner = `<div class="p-5" data-signals="${escape(JSON.stringify({ [sigNota]: "", copiado: "" }))}">
    ${banner}
    <div class="flex items-start gap-2 mb-1">
      <button data-on:click="$detailOpen=false; $selectedProp=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>
    </div>
    <p class="text-[11px] text-slate-400 -mt-5">${escape(row.meeting_corto || "")} · ${escape(row.lote_nombre || "")} · <code>${escape(row.ref || "")}</code></p>
    <h2 class="text-base font-semibold text-slate-800 mb-2 pr-6">${escape(row.titulo || "")}</h2>
    <div class="flex flex-wrap items-center gap-2 mb-3">
      ${seccionBadge(row.seccion)}
      ${row.prioridad ? `<span class="inline-flex items-center gap-1.5 text-xs text-slate-600">${priorityDot(row.prioridad)}${escape(row.prioridad)}</span>` : ""}
      <span id="decp-${escape(String(n))}">${decisionBadge(row)}</span>
    </div>
    ${invalida}
    ${pregunta}
    <dl class="text-sm space-y-1 mb-5">
      ${conContrato || row.proyecto ? dt("Proyecto", cell(row.proyecto)) : ""}
      ${conContrato || row.vence ? dt("Vence", row.vence ? `${dueFmt(row.vence)}${row.vence_estimada ? ' <span class="text-[10px] text-slate-400">estimada</span>' : ""}` : cell(null)) : ""}
      ${conContrato || asignados.length ? dt("Dueños", cell(asignados.join(", "))) : ""}
      ${conContrato || row.arquetipo ? dt("Arquetipo", a ? `<code class="text-xs text-indigo-600">${escape(a.id)}</code> · ${escape(a.name)}<span class="text-xs text-slate-400"> (${escape(a.sop)})</span>` : cell(row.arquetipo)) : ""}
    </dl>
    ${conContrato || Object.keys(slots).length ? section("Slots", null, slotsHtml) : ""}
    ${
      conContrato || row.evidencia
        ? section(
            "Evidencia",
            null,
            row.evidencia
              ? `<blockquote class="text-sm border-l-2 pl-3" style="border-color:var(--border-1);color:var(--text-2)">${escape(row.evidencia)}</blockquote>`
              : '<p class="text-xs text-slate-400 italic">— sin cita del transcript</p>'
          )
        : ""
    }
    ${row.comentario ? section("Comentario", null, `<p class="text-sm text-slate-700 whitespace-pre-wrap">${escape(row.comentario)}</p>`) : ""}
    ${section("Decisión", null, bloqueDecision(row))}
    ${section("Relacionadas · en este lote", null, bloqueLote(row, todas))}
    ${section("Relacionadas · en el cerebro", null, bloqueCerebro(row))}
  </div>`;
  return shell(inner);
}

const acts = {
  // Marca la decisión (sqlite local) y devuelve DOS parches: el panel entero y
  // el badge de la fila del maestro (`#dec-<n>`). Re-renderizar el pane
  // completo cerraría el panel — Datastar morfa por id, así que dos parches
  // quirúrgicos dejan la selección donde está.
  mark: (ctx) => {
    const n = ctx.params.get("n") || "";
    const d = ctx.params.get("d") || "";
    const nota = ctx.params.get("nota") || "";
    const args = [n, "--decision", d];
    if (nota) args.push("--nota", nota);
    const r = ctx.run(MARK, args);
    const err = r && r.ok === false ? r.error || "El script falló" : null;
    const patches = [panel(n, err)];
    if (!err) {
      let fila = null;
      try {
        fila = fetchSource("propuestas").rows.find((x) => String(x.n) === String(n));
      } catch {
        /* el panel ya reportaría el fallo de lectura */
      }
      if (fila) patches.push(`<span id="dec-${escape(String(n))}">${decisionBadge(fila)}</span>`);
    }
    return patches;
  },
};

module.exports = {
  id: "propuesta-detail",
  manifest: { slot: "detail", frag: "panel", width: WIDTH, selSignal: "selectedProp", writes: [MARK] },
  frags: { panel: (ctx) => panel(ctx.params.get("id") || "", null) },
  acts,
};
