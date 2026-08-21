#!/usr/bin/env bash
# [WRITE → WhatsApp] Onboarding del equipo al Cerebro — UN destinatario por
# corrida (nunca broadcast): a quién y cuándo lo decide el humano.
#
# Agrupa por rol contra team_members/team_roles:
#   - closer  → ya tiene ventana abierta con Iki a diario (agenda/recordatorio/
#     cierre), así que viaja como texto de sesión con --fallback-plantilla
#     onboarding_closer por si la ventana está cerrada.
#   - equipo  → primer contacto real (nunca les llegó nada de este número):
#     SIEMPRE plantilla (onboarding_equipo) — un texto de sesión aquí sería
#     ACEPTADO por Meta y fallaría después por webhook, no al instante (ver
#     docs/closers-whatsapp.md "Aprendizajes del estreno").
#
# El gancho ({{2}}) es genérico por defecto; --gancho lo personaliza (p.ej.
# Juan Camilo: sus dos assets ya vivos — dashboard del embudo + testeos VSL).
#
# Idempotente vía bash/closers/enviar.sh: escenario=onboarding-cerebro,
# ref=<nombre> — reintentar no reenvía.
#
# Usage: enviar_onboarding.sh --para <nombre|prefix> [--gancho "..."]
#                              [--grupo equipo|closer] [--dry-run] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/common.sh

PARA=""; GANCHO=""; GRUPO=""; DRY=(); JSON=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --para) PARA="$2"; shift 2 ;;
    --gancho) GANCHO="$2"; shift 2 ;;
    --grupo) GRUPO="$2"; shift 2 ;;
    --dry-run) DRY=(--dry-run); shift ;;
    --json) JSON=(--json); shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$PARA" ]] || { echo "--para es obligatorio" >&2; exit 2; }
[[ -z "$GRUPO" || "$GRUPO" == "equipo" || "$GRUPO" == "closer" ]] || { echo "--grupo debe ser equipo|closer" >&2; exit 2; }

mid="$(resolve_member "$PARA")" || exit 1
row="$(psql_ro -t -A -F'|' -c "
  SELECT trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')),
         coalesce(tr.name,'')
  FROM team_members tm
  LEFT JOIN team_roles tr ON tr.id=tm.role_id
  LEFT JOIN users u ON u.id=tm.user_id
  LEFT JOIN persons p ON p.person_id=u.person_id
  WHERE tm.id='$mid'")"
NOMBRE="${row%%|*}"; ROL="${row##*|}"
[[ -n "$NOMBRE" ]] || { echo "No se pudo resolver el nombre de $mid" >&2; exit 1; }

if [[ -z "$GRUPO" ]]; then
  case "$ROL" in *Closer*) GRUPO="closer" ;; *) GRUPO="equipo" ;; esac
fi

PRIMER="${NOMBRE%% *}"
if [[ -z "$GANCHO" ]]; then
  if [[ "$GRUPO" == "closer" ]]; then
    GANCHO="Ahora también puedo acompañarte con más que la agenda diaria."
  else
    GANCHO="Ya estoy ayudando con datos, tareas y seguimiento del equipo — quiero acompañarte con lo tuyo también."
  fi
fi

REF="${NOMBRE// /_}"

if [[ "$GRUPO" == "closer" ]]; then
  TEXTO="Hola ${PRIMER} 👋 Ya me conoces por tu agenda y tus llamadas del día. ${GANCHO} ¿Seguimos por aquí para más que eso? Responde SI."
  exec bash bash/closers/enviar.sh --para "$NOMBRE" --texto "$TEXTO" \
    --fallback-plantilla onboarding_closer \
    --escenario onboarding-cerebro --ref "$REF" "${DRY[@]}" "${JSON[@]}"
else
  exec bash bash/closers/enviar.sh --para "$NOMBRE" \
    --plantilla onboarding_equipo --vars "${PRIMER}|${GANCHO}" \
    --escenario onboarding-cerebro --ref "$REF" "${DRY[@]}" "${JSON[@]}"
fi
