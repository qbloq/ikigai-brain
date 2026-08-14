#!/usr/bin/env bash
# importar_produccion.sh — copia a la db local `reportes_llamada` el reporte que
# PRODUCCIÓN ya generó (Postgres `call_reports_gemini`, el snapshot congelado de
# lo que gemini escribió en meeting_reports antes del reemplazo de 2026-08-13,
# gemini-2.5-flash con el prompt de producción), para poder compararlo contra
# las corridas del skill sin salir de sqlite.
#
# Queda como una fila más de la misma tabla, con los dos ejes puestos:
#   generado_por    = 'gemini-2.5-flash'
#   prompt_variante = 'produccion'
# Es decir, la celda de control del experimento, guardada igual que las demás.
#
# ⚠️ EL CANDADO, y es la razón de que esto sea un script y no un pegote de SQL:
# solo importa reportes de llamadas que YA tengan una corrida propia guardada.
# Traer el reporte de gemini de una llamada todavía sin puntuar lo pone al
# alcance de la vista, y una corrida anclada no se distingue después de una
# limpia. El candado vive aquí y no en la disciplina de quien lo corre.
# `--todas` lo levanta a propósito: úsalo SOLO cuando la muestra esté cerrada.
#
# Uso: importar_produccion.sh [--todas] [--dry-run]
#
# Lee Postgres read-only y escribe sqlite vía db_exec.sh. Idempotente
# (INSERT OR REPLACE): correrlo de nuevo tras cada lote es lo esperado.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"
source "$here/../lib/sqlite.sh"

DB="reportes_llamada"
todas="" dry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --todas)   todas=1; shift ;;
    --dry-run) dry="--dry-run"; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

dbp="$(require_db "$DB")" || exit 1

if [[ -n "$todas" ]]; then
  echo "⚠️  --todas: se importa TODA la muestra, incluidas llamadas sin puntuar." >&2
  ids="$(sqlite_ro "$dbp" "SELECT group_concat(''''||meeting_id||'''') FROM muestra;")"
else
  ids="$(sqlite_ro "$dbp" "
    SELECT group_concat(''''||meeting_id||'''')
    FROM (SELECT DISTINCT meeting_id FROM reportes WHERE generado_por <> 'gemini-2.5-flash');")"
fi
[[ -z "$ids" || "$ids" == "" ]] && { echo "Nada que importar: no hay corridas propias todavía." >&2; exit 0; }

# El reporte entra tal cual está en Postgres, sin normalizar: es el control y
# tocarlo lo invalidaría. Solo se compacta el JSON para que dos filas no
# difieran por espacios en blanco.
psql_ro -t -A -c "
SELECT json_agg(json_build_object(
  'meeting_id', m.id::text,
  'fecha', to_char(m.scheduled_start_time,'YYYY-MM-DD'),
  'report', r.report))
FROM meetings m JOIN call_reports_gemini r ON r.meeting_id = m.id
WHERE m.id::text IN ($ids) AND r.report IS NOT NULL;" \
| python3 -c '
import json, sys
filas = json.load(sys.stdin) or []
def s(v): return "'"'"'" + str(v).replace("'"'"'", "'"'"''"'"'") + "'"'"'"
print("BEGIN;" if False else "", end="")
for f in filas:
    payload = json.dumps(f["report"], ensure_ascii=False, separators=(",", ":"))
    print("INSERT OR REPLACE INTO reportes "
          "(meeting_id, corrida, generado_por, prompt_variante, prompt_sha, generado_at, report, nota) VALUES ("
          + ", ".join([s(f["meeting_id"]), s(f["meeting_id"][:8] + "-produccion-gemini"),
                       s("gemini-2.5-flash"), s("produccion"), s("31e2210"), s(f["fecha"]),
                       s(payload),
                       s("importado de Postgres call_reports_gemini: es el reporte REAL de gemini, no una corrida")])
          + ");")
print(f"-- {len(filas)} reporte(s)", file=sys.stderr)
' > /tmp/.imp_prod.sql

"$here/../localdb/db_exec.sh" "$DB" - $dry < /tmp/.imp_prod.sql
rm -f /tmp/.imp_prod.sql
