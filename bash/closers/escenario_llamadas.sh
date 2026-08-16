#!/usr/bin/env bash
# [WRITE → WhatsApp] Escenarios 2 y 3 (apertura) — el TICK de llamadas (cron
# cada 5 min en horario laboral):
#
#   RECORDATORIO  llamadas que empiezan en 40–50 min → «en 45 min: <lead> +
#                 link de Meet». Mensaje de sesión (la ventana la abrió la
#                 respuesta al saludo de las 07:00); si la ventana está
#                 cerrada, cae solo a plantilla (--fallback).
#   POST-LLAMADA  llamadas cuyo fin quedó en los últimos 20 min → pregunta el
#                 resultado (Venta / Seguimiento / No Califica / No Show).
#                 La RESPUESTA la conversa Iki (protocolo post-llamada de su
#                 AGENTS.md); aquí solo se abre el flujo.
#
# Idempotente: ref = <meeting_id> por escenario; el tick puede correr siempre.
# Usage: escenario_llamadas.sh [--fallback PLANTILLA] [--dry-run] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."

FALLBACK="weekly_report"; DRY=(); FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fallback) FALLBACK="$2"; shift 2 ;;
    --dry-run) DRY=(--dry-run); shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

HOY="$(TZ=America/Bogota date +%F)"
AHORA="$(TZ=America/Bogota date +%H:%M)"

AG="$(mktemp)"; TSV="$(mktemp)"; trap 'rm -f "$AG" "$TSV"' EXIT
bash bash/closers/agenda.sh --fecha "$HOY" --json > "$AG"

# Los cuerpos viajan con \n LITERAL (se des-escapan al enviar) para que el TSV
# siga siendo una línea por mensaje.
AG="$AG" AHORA="$AHORA" python3 - > "$TSV" <<'PY'
import json, os
from datetime import datetime
rows = json.load(open(os.environ["AG"]))
ahora = datetime.strptime(os.environ["AHORA"], "%H:%M")
NL = "\\n"
for r in rows:
    if not r.get("closer"):
        continue
    ini = datetime.strptime(r["hora"], "%H:%M")
    fin = datetime.strptime(r["fin"], "%H:%M")
    delta_ini = (ini - ahora).total_seconds() / 60
    delta_fin = (ahora - fin).total_seconds() / 60
    nombre = r["closer"].split()[0]
    if 40 <= delta_ini <= 50:
        cuerpo = (f"⏰ {nombre}, en 45 minutos: *{r['lead']}* ({r['hora']}).{NL}"
                  f"{r.get('meet_url') or 'Sin link de Meet registrado'}")
        print("\t".join(["recordatorio", r["id"], r["closer"], cuerpo]))
    if 0 <= delta_fin <= 20:
        cuerpo = (f"{nombre}, ¿cómo terminó tu llamada con *{r['lead']}*?{NL}"
                  f"Responde: *Venta* / *Seguimiento* / *No Califica* / *No Show*{NL}"
                  "Si fue venta, cuéntame también el acuerdo de pago (en texto).")
        print("\t".join(["postllamada", r["id"], r["closer"], cuerpo]))
PY

RES=()
while IFS=$'\t' read -r esc mid closer cuerpo; do
  [[ -z "$esc" ]] && continue
  cuerpo="${cuerpo//\\n/$'\n'}"
  out="$(bash bash/closers/enviar.sh --para "$closer" --closer "$closer" \
    --texto "$cuerpo" --fallback-plantilla "$FALLBACK" \
    --escenario "$esc" --ref "$mid" --json "${DRY[@]}" || true)"
  RES+=("{\"escenario\":\"$esc\",\"closer\":\"$closer\",\"envio\":${out:-null}}")
done < "$TSV"

if [[ "$FORMAT" == json ]]; then
  printf '[%s]\n' "$(IFS=,; echo "${RES[*]:-}")"
else
  for r in "${RES[@]:-}"; do echo "$r"; done
  [[ ${#RES[@]} -eq 0 ]] && echo "Tick sin novedades ($(TZ=America/Bogota date +%F) $AHORA)."
fi
exit 0
