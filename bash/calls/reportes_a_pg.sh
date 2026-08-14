#!/usr/bin/env bash
# [WRITE pg] Promueve a Postgres los reportes que el pipeline del Cerebro ya
# había generado en la sqlite local `generador_reportes`.
#
# Contexto: hasta 2026-08-13 el pipeline (3 tiradas + mediana) era un prototipo
# y persistía SOLO local. Al declararse producción (migración 005), esos
# reportes ya existentes son reportes de verdad de llamadas de verdad — no hay
# razón para regenerarlos (costaría plata y daría números distintos por el ruido
# de ±4-7 puntos). Este script los sube tal cual, con sus tiradas.
#
# Idempotente por meeting: una llamada que ya tiene fila en call_reports se
# SALTA (no se duplica ni se re-versiona). Correrlo dos veces no hace nada.
# Solo promueve la ÚLTIMA generación local de cada meeting.
#
# Escaparate: por defecto también upsertea meeting_reports (reemplaza el de
# gemini, que ya quedó congelado en call_reports_gemini). --sin-escaparate lo
# omite.
#
# Uso: reportes_a_pg.sh [--db generador_reportes] [--variante mejorado2]
#                       [--sin-escaparate] [--dry-run]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
cd "$repo"
source bash/lib/common.sh
source bash/lib/sqlite.sh

db="generador_reportes"; variante="mejorado2"; escaparate=1; dry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) db="$2"; shift 2 ;;
    --variante) variante="$2"; shift 2 ;;
    --sin-escaparate) escaparate=0; shift ;;
    --dry-run) dry=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1 (ver -h)" >&2; exit 2 ;;
  esac
done

DB="$(require_db "$db")"
YA="$(psql_ro -t -A -c "SELECT string_agg(DISTINCT meeting_id::text, ',') FROM ikigaigm.call_reports")"

# El volcado es de decenas de MB (cada reporte trae sus 3 tiradas crudas), así
# que viaja por archivo: como argv revienta el límite del kernel.
FILAS_F="$(mktemp)"; trap 'rm -f "$FILAS_F"' EXIT
sqlite_ro "$DB" "
  SELECT json_group_array(json_object(
    'id', id, 'meeting_id', meeting_id, 'generacion', generacion,
    'prompt_variante', prompt_variante, 'modelo', modelo, 'n_tiradas', n_tiradas,
    'bant_budget', bant_budget, 'bant_authority', bant_authority,
    'bant_need', bant_need, 'bant_timeline', bant_timeline,
    'rango_budget', rango_budget, 'rango_authority', rango_authority,
    'rango_need', rango_need, 'rango_timeline', rango_timeline,
    'baja_confianza', baja_confianza, 'umbral_confianza', umbral_confianza,
    'arquetipo', arquetipo, 'arquetipo_votos', arquetipo_votos,
    'arquetipo_unanime', arquetipo_unanime, 'tirada_narrativa', tirada_narrativa,
    'report', report, 'generado_at', generado_at,
    'tiradas', (SELECT json_group_array(json_object('n', n, 'report', report))
                FROM tiradas WHERE reporte_id = r.id)))
  FROM reportes r
  WHERE prompt_variante = $(sql_str "$variante")
    AND generacion = (SELECT max(generacion) FROM reportes WHERE meeting_id = r.meeting_id
                      AND prompt_variante = $(sql_str "$variante"));" > "$FILAS_F"

SQL="$(YA="$YA" ESCAPARATE="$escaparate" python3 - "$FILAS_F" <<'PY'
import json, os, sys
from datetime import datetime

filas = json.loads(open(sys.argv[1]).read() or "[]")
ya = set(filter(None, (os.environ.get("YA") or "").split(",")))
esc = os.environ.get("ESCAPARATE") == "1"

def ts(v):  # generado_at viene de datetime.now() local, sin offset: pegárselo
    d = datetime.fromisoformat(v)
    return (d if d.tzinfo else d.astimezone()).isoformat()
def s(v): return "'" + str(v).replace("'", "''") + "'"
def jl(txt): return s(txt) + "::jsonb"        # el JSON ya viene serializado
def arr(xs): return ("ARRAY[" + ", ".join(s(x) for x in xs) + "]::text[]") if xs else "'{}'::text[]"

out, n = [], 0
for f in filas:
    if f["meeting_id"] in ya:
        continue
    n += 1
    m = s(f["meeting_id"])
    baja = json.loads(f["baja_confianza"] or "[]")
    vals = ", ".join([
        m, "1", s(f["prompt_variante"]), s(f["modelo"]), str(f["n_tiradas"]),
        *(str(f["bant_" + k]) for k in ("budget", "authority", "need", "timeline")),
        *(str(f["rango_" + k]) for k in ("budget", "authority", "need", "timeline")),
        arr(baja), str(f["umbral_confianza"]),
        s(f["arquetipo"]) if f["arquetipo"] else "NULL",
        jl(f["arquetipo_votos"]), "true" if f["arquetipo_unanime"] else "false",
        str(f["tirada_narrativa"]), jl(f["report"]), s(ts(f["generado_at"])) + "::timestamptz",
    ])
    tir = ", ".join(f'({t["n"]}, {jl(t["report"])})' for t in (f["tiradas"] or []))
    cols = ("meeting_id, generacion, prompt_variante, modelo, n_tiradas, "
            "bant_budget, bant_authority, bant_need, bant_timeline, "
            "rango_budget, rango_authority, rango_need, rango_timeline, "
            "baja_confianza, umbral_confianza, arquetipo, arquetipo_votos, "
            "arquetipo_unanime, tirada_narrativa, report, generado_at")
    stmt = f"""WITH nueva AS (
  INSERT INTO ikigaigm.call_reports ({cols}) VALUES ({vals}) RETURNING id
), tir AS (
  INSERT INTO ikigaigm.call_report_tiradas (call_report_id, n, report)
  SELECT nueva.id, v.n, v.rep FROM nueva, (VALUES {tir}) AS v(n, rep) RETURNING 1
)"""
    if esc:
        stmt += f"""
INSERT INTO ikigaigm.meeting_reports (meeting_id, report)
SELECT {m}, {jl(f["report"])} FROM nueva
ON CONFLICT (meeting_id) DO UPDATE SET report = EXCLUDED.report, updated_at = now();"""
    else:
        stmt += "\nSELECT count(*) FROM tir;"
    out.append(stmt)

print(f"-- {n} reportes a promover (de {len(filas)} locales; {len(filas)-n} ya estaban)",
      file=sys.stderr)
if out:
    print("BEGIN;")
    print("\n".join(out))
    print("COMMIT;")
PY
)"

if [[ -z "$SQL" ]]; then echo "Nada que promover."; exit 0; fi
if [[ -n "$dry" ]]; then
  echo "DRY-RUN: $(grep -c 'INSERT INTO ikigaigm.call_reports' <<<"$SQL") reportes; no se escribió."
  exit 0
fi
printf '%s\n' "$SQL" | psql_rw -v ON_ERROR_STOP=1 -q -f -
psql_ro -c "SELECT count(*) reportes_cerebro, count(DISTINCT meeting_id) llamadas FROM ikigaigm.call_reports"
