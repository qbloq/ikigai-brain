#!/usr/bin/env bash
# [WRITE → WhatsApp] Escenario 1 — saludo de inicio de día (07:00 COT, cron):
# a cada closer con llamadas HOY le llega su agenda (hora + lead), por
# plantilla Meta (fuera de ventana a esa hora casi siempre). Su respuesta abre
# la ventana de 24h que el resto de escenarios del día aprovecha como sesión.
#
# Idempotente vía enviar.sh: ref = <fecha>-<closer>; re-correrlo no duplica.
# Closers sin número en el directorio salen como «fallido» — visibles, jamás
# descartados en silencio. Llamadas sin closer resuelto → stderr.
#
# Usage: escenario_manana.sh [--fecha YYYY-MM-DD] [--plantilla N] [--dry-run] [--json]
#   --plantilla   default weekly_report (la aprobada heredada); cambiar a
#                 agenda_dia cuando Meta la apruebe.
set -euo pipefail
cd "$(dirname "$0")/../.."

FECHA=""; PLANTILLA="weekly_report"; DRY=(); FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fecha) FECHA="$2"; shift 2 ;;
    --plantilla) PLANTILLA="$2"; shift 2 ;;
    --dry-run) DRY=(--dry-run); shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$FECHA" ]] && FECHA="$(TZ=America/Bogota date +%F)"

TSV="$(mktemp)"; trap 'rm -f "$TSV"' EXIT
bash bash/closers/agenda.sh --fecha "$FECHA" --json | python3 -c "
import json, sys, collections
rows = json.load(sys.stdin)
por_closer = collections.defaultdict(list)
for r in rows:
    if r.get('closer'): por_closer[r['closer']].append(r)
    else: print(f\"⚠ llamada sin closer: {r['hora']} {r['lead']}\", file=sys.stderr)
for closer, calls in sorted(por_closer.items()):
    lista = ' · '.join(f\"{c['hora']} {c['lead']}\" for c in calls)
    cuerpo = (f'Tus llamadas de hoy ({len(calls)}): {lista} — '
              'Responde OK y te recuerdo cada una 45 minutos antes con su link de Meet.')
    print('\t'.join([closer, closer.split()[0], cuerpo]))
" > "$TSV"

RES=()
while IFS=$'\t' read -r closer nombre cuerpo; do
  [[ -z "$closer" ]] && continue
  out="$(bash bash/closers/enviar.sh --para "$closer" --closer "$closer" \
    --plantilla "$PLANTILLA" --vars "$nombre|$cuerpo" \
    --escenario manana --ref "$FECHA-${closer// /_}" --json "${DRY[@]}" || true)"
  RES+=("{\"closer\":\"$closer\",\"envio\":${out:-null}}")
done < "$TSV"

if [[ "$FORMAT" == json ]]; then
  printf '[%s]\n' "$(IFS=,; echo "${RES[*]:-}")"
else
  for r in "${RES[@]:-}"; do echo "$r"; done
  [[ ${#RES[@]} -eq 0 ]] && echo "Sin llamadas con closer para $FECHA."
fi
exit 0
