#!/usr/bin/env bash
# El objeto-resumen del interceptor: KPIs del webhook (24h/7d), últimas
# corridas de reconciliación y su drift — la fuente de la UI viz
# «Intercepciones». Siempre un solo objeto JSON. Read-only.
# uso: resumen.sh [--json]   (--json aceptado por consistencia; siempre emite JSON)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

WEBHOOK="$(echo "SELECT
    sum(CASE WHEN recibido_at >= datetime('now','-1 day') THEN 1 ELSE 0 END) AS h24,
    sum(CASE WHEN recibido_at >= datetime('now','-1 day') AND ok=1 THEN 1 ELSE 0 END) AS h24_ok,
    sum(CASE WHEN recibido_at >= datetime('now','-7 day') THEN 1 ELSE 0 END) AS d7,
    sum(CASE WHEN recibido_at >= datetime('now','-7 day') AND ok=1 THEN 1 ELSE 0 END) AS d7_ok
  FROM crm_webhook;" | int_sql -json)"
FALLOS="$(echo "SELECT recibido_at, appointment_id, contacto, error FROM crm_webhook
  WHERE ok=0 ORDER BY recibido_at DESC LIMIT 5;" | int_sql -json)"
CORRIDAS="$(echo "WITH ultimas AS (SELECT max(id) AS id FROM corridas GROUP BY ghl_calendar_id)
  SELECT id, corrida_at, proyecto, ghl_calendar_id, ghl_total, db_total,
         coinciden, discrepancias, estado, detalle
  FROM corridas WHERE id IN (SELECT id FROM ultimas) ORDER BY proyecto;" | int_sql -json)"
DRIFT="$(echo "WITH ultimas AS (SELECT max(id) AS id FROM corridas WHERE estado='ok' GROUP BY ghl_calendar_id)
  SELECT d.corrida_id, c.proyecto, d.tipo, d.appointment_id, d.meeting_id, d.detalle
  FROM drift d JOIN corridas c ON c.id = d.corrida_id
  WHERE d.corrida_id IN (SELECT id FROM ultimas) ORDER BY c.proyecto, d.tipo;" | int_sql -json)"

python3 -c '
import json, sys
from datetime import datetime, timezone
wh = (json.loads(sys.argv[1]) or [{}])[0]
def num(v): return int(v) if v is not None else 0
h24, h24ok, d7, d7ok = (num(wh.get(k)) for k in ("h24","h24_ok","d7","d7_ok"))
print(json.dumps({
  "webhook": {"h24": {"recibidos": h24, "ok": h24ok, "fallos": h24 - h24ok},
              "d7": {"recibidos": d7, "ok": d7ok, "fallos": d7 - d7ok},
              "ultimos_fallos": json.loads(sys.argv[2]) or []},
  "corridas": json.loads(sys.argv[3]) or [],
  "drift": json.loads(sys.argv[4]) or [],
  "generado_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}, ensure_ascii=False))' "${WEBHOOK:-[]}" "${FALLOS:-[]}" "${CORRIDAS:-[]}" "${DRIFT:-[]}"
