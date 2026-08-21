#!/usr/bin/env bash
# testeos.sh — el HISTÓRICO de testeos del embudo, como filas. Read-only.
#
# El registro que la alineación DG 2026-08-19 pidió: cada testeo con sus
# métricas iniciales y finales congeladas (snapshots de bash/metrics/embudo.sh)
# y su desenlace. Vive en Postgres (ikigaigm.testeos, migración 006) porque lo
# crean y monitorean los copilotos del rol Ejecutivo — un histórico compartido
# no puede vivir en la sqlite de una máquina. Las escrituras están en
# testeo_abrir.sh / testeo_cerrar.sh; esta lista es el visor (y alimenta la
# fuente `testeos` del viz, que muestra el id corto como handle).
#
# Uso: testeos.sh [--estado en_curso|cerrado|abortado] [--step S]
#                 [--project N] [--limit N] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

estado="" step="" project="" limit=50
while [[ $# -gt 0 ]]; do
  case "$1" in
    --estado)  estado="$2"; shift 2 ;;
    --step)    step="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --limit)   limit="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit debe ser entero (0 = sin tope)" >&2; exit 2; }

esc() { printf '%s' "$1" | sed "s/'/''/g"; }
where="1=1"
[[ -n "$estado"  ]] && where="$where AND t.estado='$(esc "$estado")'"
[[ -n "$step"    ]] && where="$where AND t.step='$(esc "$step")'"
[[ -n "$project" ]] && where="$where AND pr.name ILIKE '%$(esc "$project")%'"
lim=""; [[ "$limit" != 0 ]] && lim="LIMIT $((limit))"

emit "
SELECT left(t.id::text,8)                                    AS id,
       pr.name                                               AS proyecto,
       t.step,
       t.variable,
       coalesce(t.metrica,'—')                               AS metrica,
       t.estado,
       to_char(t.abierto_en AT TIME ZONE 'America/Bogota','YYYY-MM-DD HH24:MI') AS abierto,
       coalesce(to_char(t.cerrado_en AT TIME ZONE 'America/Bogota','YYYY-MM-DD HH24:MI'),'—') AS cerrado,
       t.valor_inicial, t.valor_final, t.delta,
       coalesce(t.resultado,'—')                             AS resultado,
       t.abierto_por,
       coalesce(t.decision,'')                               AS decision
FROM testeos t
JOIN projects pr ON pr.id = t.project_id
WHERE $where
ORDER BY (t.estado='en_curso') DESC, t.abierto_en DESC
$lim"
