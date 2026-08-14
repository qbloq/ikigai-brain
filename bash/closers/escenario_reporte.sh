#!/usr/bin/env bash
# [WRITE → WhatsApp] Escenario 6 — el reporte de la llamada, de vuelta al closer.
#
# Cierra el lazo que abrió el pipeline de generación: cuando `call_reports` ya
# tiene el reporte del Cerebro de una llamada (transcript → 3 tiradas → mediana),
# este script le manda al closer lo ACCIONABLE de ese reporte y, aparte, al
# Director Comercial el número.
#
# QUÉ VE CADA UNO (decisión de diseño, no detalle de formato):
#   · El CLOSER recibe coaching SIN puntaje: una fortaleza concreta, una cosa a
#     corregir y el siguiente paso con ese lead. Un puntaje desnudo por WhatsApp
#     se lee como calificación, no como ayuda, y el reporte trae material mucho
#     más útil que un 6.5. `--con-puntaje` lo incluye si se decide lo contrario.
#   · El DIRECTOR COMERCIAL (--dc) recibe el número: puntaje de la llamada, BANT
#     con sus banderas de baja confianza, prioridad y probabilidad. Ese es su
#     tablero — y las banderas importan: un ítem con rango > umbral entre
#     tiradas NO es un dato, es una duda.
#
# El texto sale del reporte tal cual (fortalezas, mejoras, estrategia de cierre);
# este script no interpreta ni resume con un modelo — recorta y arma.
#
# Idempotente por (escenario, ref=meeting_id) como todos los demás.
#
# Usage: escenario_reporte.sh [--desde-horas N] [--dc NOMBRE] [--con-puntaje]
#                             [--limit N] [--dry-run] [--json]
#   --desde-horas N  reportes generados en las últimas N horas (default 24)
#   --dc NOMBRE      además, manda el resumen numérico a esa persona
#                    (default: nadie; el uso previsto es --dc Lucho)
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/common.sh

HORAS=24; DC=""; PUNTAJE=0; LIMIT=20; DRY=(); FORMAT=text; FALLBACK="weekly_report"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde-horas) HORAS="$2"; shift 2 ;;
    --dc) DC="$2"; shift 2 ;;
    --con-puntaje) PUNTAJE=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --fallback) FALLBACK="$2"; shift 2 ;;
    --dry-run) DRY=(--dry-run); shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$HORAS" =~ ^[0-9]+$ && "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--desde-horas/--limit enteros" >&2; exit 2; }

DATOS="$(psql_ro -t -A -c "
SELECT json_agg(x) FROM (
  SELECT left(m.id::text,8) AS id, m.id::text AS uuid,
    to_char(m.scheduled_start_time AT TIME ZONE 'UTC','DD/MM HH24:MI') AS cuando,
    regexp_replace(m.name, ' *[-|–] *.*\$', '') AS lead,
    cl.closer, cr.report, cr.bant_budget, cr.bant_authority, cr.bant_need,
    cr.bant_timeline, cr.baja_confianza
  FROM ikigaigm.call_reports cr
  JOIN meetings m ON m.id = cr.meeting_id
  LEFT JOIN LATERAL (
    SELECT nullif(trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')),'') AS closer
    FROM crm_contacts c
    JOIN crm_opportunities o ON o.contact_id=c.id
    LEFT JOIN users u ON u.id=o.user_id
    LEFT JOIN persons p ON p.person_id=u.person_id
    WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
    ORDER BY (o.project_id = m.project_id) DESC NULLS LAST, o.created_date DESC
    LIMIT 1
  ) cl ON true
  WHERE cr.generado_at >= now() - interval '$HORAS hours'
    AND cl.closer IS NOT NULL
  ORDER BY cr.generado_at DESC
  LIMIT $LIMIT
) x")"

TSV="$(mktemp)"; trap 'rm -f "$TSV"' EXIT
DATOS="${DATOS:-[]}" PUNTAJE="$PUNTAJE" DC="$DC" python3 - > "$TSV" <<'PY'
import json, os
NL = "\\n"

def recorta(t, n=230):
    t = " ".join((t or "").split())
    if len(t) <= n:
        return t
    corte = t[:n]
    # cortar en frontera de palabra: media palabra en WhatsApp se lee como error
    return corte[:corte.rfind(" ")] + "…"

PRIO = {"HIGH": "ALTA", "MEDIUM": "MEDIA", "LOW": "BAJA"}

def primero(d, *ruta, default=None):
    for k in ruta:
        if not isinstance(d, dict):
            return default
        d = d.get(k)
    return d if d is not None else default

filas = json.loads(os.environ["DATOS"] or "[]") or []
con_puntaje = os.environ["PUNTAJE"] == "1"
dc = os.environ["DC"]

for f in filas:
    r = json.loads(f["report"]) if isinstance(f["report"], str) else f["report"]
    nombre = f["closer"].split()[0]
    ev = primero(r, "performanceInsights", "finalCloserEvaluation", default={}) or {}
    fuerzas = (primero(ev, "strengths", "items", default=[]) or [])
    mejoras = (primero(ev, "areasForImprovement", "items", default=[]) or [])
    pred = primero(r, "leadProfile", "predictionsAndRecommendations", default={}) or {}
    estrategia = pred.get("recommendedClosingStrategy") or []
    prob = primero(pred, "closingProbability", "percentage")
    prio = primero(r, "leadProfile", "intelligentSegmentation",
                   "priorityClassification", "priority")

    partes = [f"{nombre}, ya analicé tu llamada con *{f['lead']}* ({f['cuando']}).", ""]
    if fuerzas:
        partes += [f"✅ Bien hecho: {recorta(fuerzas[0])}", ""]
    if mejoras:
        partes += [f"🔧 Para la próxima: {recorta(mejoras[0])}", ""]
    señal = []
    if prio:
        señal.append(f"prioridad {PRIO.get(prio, prio)}")
    if isinstance(prob, (int, float)):
        señal.append(f"prob. de cierre {prob}%")
    if con_puntaje and isinstance(ev.get("overallScore"), (int, float)):
        señal.append(f"puntaje {ev['overallScore']}/10")
    if señal:
        partes.append("🎯 " + " · ".join(señal))
    if estrategia:
        partes.append(f"Siguiente paso: {recorta(estrategia[0])}")
    cuerpo = NL.join(p for p in partes).strip()
    print("\t".join(["reporte", f["uuid"], f["closer"], cuerpo]))

    if dc:
        baja = f["baja_confianza"] or []
        if isinstance(baja, str):
            baja = [b for b in baja.strip("{}").split(",") if b]
        bant = " ".join(f"{k[0].upper()}{int(f['bant_' + k])}"
                        for k in ("budget", "authority", "need", "timeline"))
        score = ev.get("overallScore")
        linea = [f"📊 *{f['closer']}* · {f['lead']} ({f['cuando']})",
                 f"Puntaje de llamada: {score}/10" if score is not None else "Puntaje: —",
                 f"BANT {bant}" + (f"  ⚠️ baja confianza: {', '.join(baja)}" if baja else ""),
                 f"Prioridad {PRIO.get(prio, prio) or '—'} · prob. {prob if prob is not None else '—'}%"]
        print("\t".join(["reporte_dc", f["uuid"], dc, NL.join(linea)]))
PY

RES=()
while IFS=$'\t' read -r esc mid quien cuerpo; do
  [[ -z "$esc" ]] && continue
  cuerpo="${cuerpo//\\n/$'\n'}"
  out="$(bash bash/closers/enviar.sh --para "$quien" --closer "$quien" \
    --texto "$cuerpo" --fallback-plantilla "$FALLBACK" \
    --escenario "$esc" --ref "$mid" --json "${DRY[@]}" || true)"
  RES+=("{\"escenario\":\"$esc\",\"para\":\"$quien\",\"envio\":${out:-null}}")
done < "$TSV"

if [[ "$FORMAT" == json ]]; then
  printf '[%s]\n' "$(IFS=,; echo "${RES[*]:-}")"
else
  for r in "${RES[@]:-}"; do echo "$r"; done
  [[ ${#RES[@]} -eq 0 ]] && echo "Sin reportes nuevos en las últimas $HORAS h."
fi
