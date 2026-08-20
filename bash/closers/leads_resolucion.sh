#!/usr/bin/env bash
# leads_resolucion.sh — la cola de VENTAS POR RESOLVER de un closer: los leads
# curados en la sqlite local `ventas_mateo.leads_agosto` (pareados a mano con
# CRM + meetings — ver la tabla), cruzados EN VIVO contra Postgres para saber
# cuáles ya tienen plan de pago (payment_plans por customer_id=ghl_contact_id).
# El estado NUNCA se escribe en la sqlite: se deriva del sistema — crear el
# plan (vía la UI `resolver-ventas` o como sea) es lo que resuelve la fila.
#
# estado: 'resuelto'   → ya existe un plan Active para ese contacto creado
#                        desde --desde (default 2026-08-01)
#         'pendiente'  → pareo completo o sin_meeting, sin plan aún
#         'bloqueado'  → pareo=no_encontrado (sin contacto GHL: no hay a quién
#                        colgarle el plan)
#
# Alimenta la fuente viz `leads_resolucion` (UI `resolver-ventas`).
#
# Uso: leads_resolucion.sh [--db NOMBRE] [--tabla T] [--desde YYYY-MM-DD] [--json]
# Read-only (sqlite_ro + psql_ro).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/sqlite.sh"

DB="ventas_mateo" TABLA="leads_agosto" DESDE="2026-08-01"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)    DB="$2"; shift 2 ;;
    --tabla) TABLA="$2"; shift 2 ;;
    --desde) DESDE="$2"; shift 2 ;;
    --json)  FORMAT=json; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$TABLA" =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "--tabla inválida" >&2; exit 2; }
[[ "$DESDE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--desde debe ser YYYY-MM-DD" >&2; exit 2; }

DB_PATH="$(require_db "$DB")"
# tr -d '\n': sqlite -json separa filas con \n (los \n de contenido van escapados),
# y el merge de abajo pasa los dos documentos por stdin separados por UN salto.
LEADS_JSON="$(sqlite_ro "$DB_PATH" -json "SELECT * FROM \"$TABLA\" ORDER BY n" 2>/dev/null | tr -d '\n' || true)"
[[ -z "$LEADS_JSON" ]] && LEADS_JSON='[]'

# ids de contacto con comillas SQL, solo los no nulos
IDS="$(printf '%s' "$LEADS_JSON" | python3 -c "
import json,sys
rows=json.load(sys.stdin)
ids=sorted({r['ghl_contact_id'] for r in rows if r.get('ghl_contact_id')})
print(','.join(\"'\"+i+\"'\" for i in ids if i.replace('_','').isalnum()))")"

PLANES_JSON='[]'
if [[ -n "$IDS" ]]; then
  PLANES_JSON="$(psql_ro -At <<SQL
SELECT coalesce(json_agg(t), '[]') FROM (
  SELECT pp.customer_id, pp.plan_id, pp.created_at::date AS plan_creado,
         pp.original_amount, pp.number_of_installments, pp.plan_status,
         (SELECT count(*) FROM ikigaigm.installments i
           WHERE i.plan_id = pp.plan_id AND i.status = 'Paid') AS cuotas_pagadas
  FROM ikigaigm.payment_plans pp
  WHERE pp.customer_id IN ($IDS) AND pp.created_at >= '$DESDE'
  ORDER BY pp.created_at DESC
) t
SQL
)"
  PLANES_JSON="$(printf '%s' "$PLANES_JSON" | tr -d '\n')"
fi

printf '%s\n%s' "$LEADS_JSON" "$PLANES_JSON" | python3 -c "
import json, sys
leads_raw, planes_raw = sys.stdin.read().split('\n', 1)
leads = json.loads(leads_raw or '[]')
planes = json.loads(planes_raw or '[]')
por_contacto = {}
for p in planes:
    por_contacto.setdefault(p['customer_id'], p)  # el más reciente (ya ordenado DESC)
out = []
for r in leads:
    plan = por_contacto.get(r.get('ghl_contact_id') or '')
    if plan:
        r['estado'] = 'resuelto'
        r['plan_id'] = plan['plan_id']
        r['plan_creado'] = plan['plan_creado']
        r['plan_monto'] = plan['original_amount']
        r['plan_cuotas'] = plan['number_of_installments']
        r['plan_cuotas_pagadas'] = plan['cuotas_pagadas']
    else:
        r['estado'] = 'bloqueado' if r.get('pareo') == 'no_encontrado' else 'pendiente'
    out.append(r)
print(json.dumps(out, ensure_ascii=False))
" | if [[ "${FORMAT:-text}" == json ]]; then cat; else
  python3 -c "
import json, sys
rows = json.load(sys.stdin)
for r in rows:
    print(f\"{r['n']:>2}  {r['lead'][:32]:32} {str(r.get('monto_reportado') or '?'):>7}  {r['pareo']:13} {r['estado']:9} plan={r.get('plan_id','—')}\")"
fi
