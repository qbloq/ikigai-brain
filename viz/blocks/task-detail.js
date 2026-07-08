// task-detail block (#task-detail) — view-only detail panel for one task:
// header + provenance chip + activity card + inputs/outputs (IO) + acceptance
// criteria (validation) + comments. SSE-patched by the /task/:id route.
// Also exports the activity/provenance cards shared with the IO editor.

const { fetchSource } = require("../lib/datasources");
const { escape, cell, section, dueFmt, PRIORITY_DOT } = require("../lib/kit");

const STATUS_BADGE = {
  pending: "bg-amber-100 text-amber-700",
  in_progress: "bg-blue-100 text-blue-700",
  completed: "bg-emerald-100 text-emerald-700",
  blocked: "bg-red-100 text-red-700",
  cancelled: "bg-slate-200 text-slate-600",
};
const STATUS_ES = {
  pending: "Pendiente",
  in_progress: "En progreso",
  completed: "Completada",
  blocked: "Bloqueada",
  cancelled: "Cancelada",
};

// The inner SSE target. Fixed width (w-96) so content doesn't reflow while the
// persistent #detail-wrap animates its width open/closed — it slides into view.
function panelShell(inner) {
  return `<div id="task-detail" class="w-96 h-full overflow-y-auto">${inner}</div>`;
}

function taskDetailEmpty() {
  return panelShell(
    `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
      <p>Selecciona una tarea para ver su detalle.</p>
    </div>`
  );
}

function doneMark(ok, okT, noT) {
  return ok
    ? `<span class="text-emerald-600 shrink-0" title="${escape(okT)}">✓</span>`
    : `<span class="text-slate-300 shrink-0" title="${escape(noT)}">○</span>`;
}

function ioList(items, doneKey, okT, noT) {
  if (!items || !items.length) return '<p class="text-xs text-slate-400 italic">— ninguno</p>';
  return `<ul class="space-y-1.5">${items
    .map(
      (it) => `<li class="flex items-start gap-2">
        ${doneMark(it[doneKey], okT, noT)}
        <div class="min-w-0">
          <p class="text-sm text-slate-700">${escape(it.title)}</p>
          <p class="text-xs text-slate-400">${escape(it.io_type || "—")}${it.is_required ? "" : " · opcional"}</p>
        </div>
      </li>`
    )
    .join("")}</ul>`;
}

function criteriaList(items) {
  if (!items || !items.length) return '<p class="text-xs text-slate-400 italic">— sin criterios</p>';
  return `<ul class="space-y-1.5">${items
    .map(
      (c) => `<li class="flex items-start gap-2">
        ${doneMark(c.is_met, "cumplido", "pendiente")}
        <div class="min-w-0">
          <p class="text-sm text-slate-700">${escape(c.criterion)}</p>
          <p class="text-xs text-slate-400">${escape(c.method || "—")}${c.is_required ? "" : " · opcional"} · sobre: ${escape(c.output || "—")}</p>
        </div>
      </li>`
    )
    .join("")}</ul>`;
}

function commentsList(items) {
  if (!items || !items.length) return '<p class="text-xs text-slate-400 italic">— sin comentarios</p>';
  return `<ul class="space-y-2.5">${items
    .map(
      (c) => `<li>
        <div class="flex items-baseline gap-2 text-xs text-slate-400 mb-0.5">
          <span class="font-medium text-slate-600">${escape(c.author || "—")}</span>
          <span>${escape(c.date || "")}</span>
        </div>
        <p class="text-sm text-slate-700 whitespace-pre-wrap">${escape(c.text || "")}</p>
      </li>`
    )
    .join("")}</ul>`;
}

// The Actividad → SOP card (archetype id + name/verb, with its macro › sop path).
// Shared by the read-only detail panel and the IO editor. `a` is d.archetype
// (null when the task is untagged → renders nothing).
function activityBlock(a) {
  if (!a) return "";
  return `<div class="mb-5 rounded-lg bg-indigo-50 border border-indigo-100 px-3 py-2">
    <p class="text-[11px] font-semibold uppercase tracking-wide text-indigo-400">Actividad</p>
    <p class="text-sm text-slate-800"><span class="font-mono text-xs text-indigo-600">${escape(a.id)}</span> · ${escape(a.name)}${a.verb ? ` <span class="text-xs text-slate-400">(${escape(a.verb)})</span>` : ""}</p>
    ${a.sop ? `<p class="text-xs text-slate-400 mt-0.5">${escape(a.macro)} ${escape(a.macro_name || "")} › ${escape(a.sop)} ${escape(a.sop_name || "")}</p>` : ""}
  </div>`;
}

// Provenance chip: where the task came from. Notion → clickable ↗ link; meeting
// → its name; manual/other → a label. Empty when the task has no source.
function sourceBlock(s) {
  if (!s || typeof s !== "object" || Array.isArray(s)) return "";
  const T = {
    notion: { icon: "📄", label: "Notion" },
    meeting: { icon: "🎙️", label: "Reunión" },
    manual: { icon: "✍️", label: "Manual" },
    other: { icon: "🔗", label: "Externo" },
  };
  const t = T[s.type] || { icon: "🔗", label: s.type || "Origen" };
  let inner;
  if (s.url) {
    inner = `<a href="${escape(s.url)}" target="_blank" class="text-indigo-600 hover:underline truncate">${escape(t.label)} ↗</a>`;
  } else if (s.meeting_name || s.meeting_id) {
    inner = `<span class="text-slate-700 truncate">${escape(t.label)} · ${escape(s.meeting_name || s.meeting_id)}</span>`;
  } else if (s.type) {
    inner = `<span class="text-slate-700">${escape(t.label)}</span>`;
  } else {
    return "";
  }
  return `<div class="mb-5 flex items-center gap-1.5 text-xs bg-slate-50 border border-slate-200 rounded px-2.5 py-1.5">
    <span class="text-[11px] font-semibold uppercase tracking-wide text-slate-400 shrink-0">Origen</span>
    <span class="shrink-0">${t.icon}</span>${inner}
  </div>`;
}

function renderTaskDetail(id) {
  if (!id) return taskDetailEmpty();
  let d, err;
  try {
    const { rows } = fetchSource("task_detail", { id });
    d = rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err || !d) {
    return panelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(err || "Tarea no encontrada")}</div></div>`
    );
  }
  const badge = STATUS_BADGE[d.status] || "bg-slate-100 text-slate-600";
  const prio = PRIORITY_DOT[d.priority];
  const header = `<div class="flex items-start gap-2 mb-1">
      <button data-on:click="$detailOpen=false; $selectedTask=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>
    </div>
    <h2 class="text-base font-semibold text-slate-800 mb-2 -mt-6 pr-6">${escape(d.title)}</h2>
    <div class="flex flex-wrap items-center gap-2 mb-3">
      <span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${badge}">${escape(STATUS_ES[d.status] || d.status)}</span>
      ${prio ? `<span class="inline-flex items-center gap-1.5 text-xs text-slate-600"><span class="inline-block w-2.5 h-2.5 rounded-full ${prio.c}"></span>${escape(prio.t)}</span>` : ""}
    </div>
    <dl class="text-sm space-y-1 mb-5">
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Proyecto</dt><dd class="text-slate-700">${cell(d.project)}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Responsables</dt><dd class="text-slate-700">${cell(d.assignees)}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Vence</dt><dd class="text-slate-700">${dueFmt(d.due)}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Creada</dt><dd class="text-slate-700">${dueFmt(d.created)}</dd></div>
    </dl>`;

  const inner = `<div class="p-5">
    ${header}
    ${sourceBlock(d.source)}
    ${activityBlock(d.archetype)}
    ${section("Inputs", (d.inputs || []).length, ioList(d.inputs, "is_satisfied", "satisfecho", "pendiente"))}
    ${section("Outputs", (d.outputs || []).length, ioList(d.outputs, "is_delivered", "entregado", "pendiente"))}
    ${section("Validación", (d.criteria || []).length, criteriaList(d.criteria))}
    ${section("Comentarios", (d.comments || []).length, commentsList(d.comments))}
  </div>`;
  return panelShell(inner);
}

// Routed block (paso 3): registers its SSE fragment in the flat component
// namespace. Canonical: GET /c/task-detail/frag/panel?id=… — alias GET
// /task/:id (empty id → the empty state, which is how the panel "closes").
// Detail-slot manifest: how the master-detail pattern wires this panel —
// which frag a row click opens, the open-panel width (matches the inner
// shell's w-96) and the selection signal its close button clears.
module.exports = {
  id: "task-detail",
  manifest: { slot: "detail", frag: "panel", width: "24rem", selSignal: "selectedTask" },
  frags: { panel: (ctx) => renderTaskDetail(ctx.params.get("id") || "") },
  renderTaskDetail,
  activityBlock,
  sourceBlock,
};
