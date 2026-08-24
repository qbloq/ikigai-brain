#!/usr/bin/env bash
# [WRITE local] Cargar UN backup de propuestas (su gemelo JSON) en la sqlite
# local `propuestas_reuniones`: una fila en `lotes` + una por propuesta.
# Idempotente por reunión: si el lote ya existe se NIEGA (la UI deja de
# ofrecer el botón). Cada contrato §A se valida con create_task.sh --dry-run
# (nombres, proyecto, arquetipo, slots); el que falla se carga igual con
# valida=0 + el error, para que se vea y se corrija en el JSON.
#
# Usage: propuesta_cargar.sh <meeting-id|prefijo8> [--dry-run] [--json]
#   --json  {ok, meeting_id, n_a, n_b, invalidas:[ref…]}
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
cd "$REPO_ROOT"

ID=""; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *) ID="$1"; shift ;;
  esac
done
fail() { if [[ "$FORMAT" == json ]]; then jq -cn --arg e "$1" '{ok:false,error:$e}'; else echo "$1" >&2; fi; exit "${2:-1}"; }
[[ "$ID" =~ ^[0-9a-f]{8} ]] || fail "Falta <meeting-id|prefijo8>" 2
corto="${ID:0:8}"
JS="backups/meeting-tasks/$corto.json"
[[ -f "$JS" ]] || fail "No existe $JS — el backup no tiene gemelo estructurado (lo genera el cerebro desde el .md)"

DBP="$(db_path propuestas_reuniones)"; mkdir -p "$LOCALDB_DIR"
sqlite_rw "$DBP" < bash/localdb/propuestas_schema.sql
meeting="$(jq -r .meeting "$JS")"
if [[ -n "$(sqlite_ro "$DBP" "SELECT 1 FROM lotes WHERE meeting_id=$(sql_str "$meeting") OR meeting_corto=$(sql_str "$corto");")" ]]; then
  fail "El lote $corto ya está cargado — un backup se carga una sola vez"
fi

# Validar cada contrato §A contra Postgres (dry-run: nada se escribe). Se
# itera con `jq -c '.propuestas[]'` (una línea JSON por propuesta) y cada
# campo se extrae con `jq -r`/`jq -c` dentro del bucle — más lento que @tsv
# pero sin sus escapes de tabs/newlines, que corromperían el JSON del
# contrato (backslashes duplicados) al insertarlo.
declare -A ERR
while IFS= read -r linea; do
  ref="$(jq -r '.ref' <<<"$linea")"
  contrato="$(jq -c '.contrato' <<<"$linea")"
  if ! msg="$(printf '%s' "$contrato" | bash bash/tasks/create_task.sh - --dry-run 2>&1 >/dev/null)"; then
    ERR["$ref"]="$(printf '%s' "$msg" | tail -5 | tr '\n' ' ')"
  fi
done < <(jq -c '.propuestas[]|select(.seccion=="A")' "$JS")

# Un INSERT por propuesta.
sql="BEGIN;
INSERT INTO lotes (meeting_id, meeting_corto, archivo, fecha, nombre, cargado_en, n_a, n_b) VALUES (
  $(sql_str "$meeting"), $(sql_str "$corto"), $(sql_str "$corto.md"),
  $(sql_str "$(jq -r '.fecha//""' "$JS")"), $(sql_str "$(jq -r '.nombre//""' "$JS")"),
  datetime('now'),
  $(jq '[.propuestas[]|select(.seccion=="A")]|length' "$JS"), $(jq '[.propuestas[]|select(.seccion=="B")]|length' "$JS"));
"
while IFS= read -r linea; do
  ref="$(jq -r '.ref' <<<"$linea")"
  seccion="$(jq -r '.seccion' <<<"$linea")"
  titulo="$(jq -r '.contrato.title // .titulo // ""' <<<"$linea")"
  proyecto="$(jq -r '.contrato.project // ""' <<<"$linea")"
  prioridad="$(jq -r '.contrato.priority // ""' <<<"$linea")"
  vence="$(jq -r '.contrato.due_date // ""' <<<"$linea")"
  vest="$(jq -r 'if .vence_estimada then 1 else 0 end' <<<"$linea")"
  asign="$(jq -c '(.contrato.assignee // [])' <<<"$linea")"
  arq="$(jq -r '.contrato.archetype // ""' <<<"$linea")"
  slots="$(jq -c '(.contrato.slots // {})' <<<"$linea")"
  evid="$(jq -r '.evidencia // ""' <<<"$linea")"
  com="$(jq -r '.comentario // ""' <<<"$linea")"
  preg="$(jq -r '.pregunta // ""' <<<"$linea")"
  accs="$(jq -r '.accion_sugerida // ""' <<<"$linea")"
  rel="$(jq -c '(.relacionadas // [])' <<<"$linea")"
  dep="$(jq -c '(.depende_de // [])' <<<"$linea")"
  contrato="$(jq -c '.contrato' <<<"$linea")"

  err="${ERR[$ref]:-}"; valida=1; [[ -n "$err" ]] && valida=0
  sql+="INSERT INTO propuestas (meeting_id, ref, seccion, titulo, proyecto, prioridad, vence, vence_estimada, asignados, arquetipo, slots, evidencia, comentario, pregunta, accion_sugerida, relacionadas, depende_de, contrato, valida, error_validacion) VALUES (
    $(sql_str "$meeting"), $(sql_str "$ref"), $(sql_str "$seccion"), $(sql_str "$titulo"), $(sql_str "$proyecto"), $(sql_str "$prioridad"), $(sql_str "$vence"), $vest,
    $(sql_str "$asign"), $(sql_str "$arq"), $(sql_str "$slots"), $(sql_str "$evid"), $(sql_str "$com"), $(sql_str "$preg"), $(sql_str "$accs"),
    $(sql_str "$rel"), $(sql_str "$dep"), $( [[ "$contrato" == null ]] && echo NULL || sql_str "$contrato" ), $valida, $( [[ -n "$err" ]] && sql_str "$err" || echo NULL ));
"
done < <(jq -c '.propuestas[]' "$JS")
sql+=$([[ "$DRY" == 1 ]] && echo "ROLLBACK;" || echo "COMMIT;")
sqlite_rw "$DBP" "$sql"

refs="$(printf '%s\n' "${!ERR[@]}" 2>/dev/null)"
if [[ -z "$refs" ]]; then inval="[]"; else inval="$(printf '%s\n' "$refs" | jq -R . | jq -sc .)"; fi
if [[ "$FORMAT" == json ]]; then
  jq -cn --arg m "$meeting" --argjson na "$(jq '[.propuestas[]|select(.seccion=="A")]|length' "$JS")" --argjson nb "$(jq '[.propuestas[]|select(.seccion=="B")]|length' "$JS")" --argjson inv "${inval:-[]}" --argjson dry "$DRY" '{ok:true, meeting_id:$m, n_a:$na, n_b:$nb, invalidas:$inv, dry_run:($dry==1)}'
else
  echo "Lote $corto cargado: $(jq '[.propuestas[]|select(.seccion=="A")]|length' "$JS") §A + $(jq '[.propuestas[]|select(.seccion=="B")]|length' "$JS") §B; inválidas: ${inval:-[]}$([[ "$DRY" == 1 ]] && echo ' (dry-run, rollback)')"
fi
