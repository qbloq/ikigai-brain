#!/usr/bin/env bash
# WRITE (local): set the curation marks of ONE row of the `cruce` table in the
# pm_platform SQLite db — the reconciliation between the PM platform's tasks
# and the cerebro's. This is the ONLY write the viz `cruce` UI performs (via
# its Merge/resuelta buttons): a curation mark on LOCAL data, never Postgres.
# The real merge is executed later, from the conversation, by
# bash/tasks/merge_from_cruce.sh over the rows marked here.
#
# Usage: cruce_mark.sh <n> [--merge 0|1] [--resuelta 0|1] [--resolucion TEXT] [--json]
#   <n>            row key (cruce.n)
#   --merge 0|1    toggle the merge mark (curaduría de mezcla)
#   --resuelta 0|1 toggle the resolved flag; 1 stamps resuelta_en (UTC),
#                  0 clears it and the resolucion
#   --resolucion   free text recording HOW it was resolved
#   --json         {ok, n, merge, resuelta, resolucion, resuelta_en}
#
# Guardrails: merge can only be set on veredicto='igual' AND confianza='alta'
# rows (the only ones the UI offers the button for), a resolved row can't take
# new merge marks, and no two rows pointing at the SAME cerebro task can be
# marked at once — the PM platform duplicates tasks internally (the endpoints
# spec is tripled), so several rows legitimately share a ce_id; merging two of
# them would duplicate that cerebro task twice and cancel it twice.
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

DB=pm_platform
n="" merge="" resuelta="" resolucion="" json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --merge)      merge="$2"; shift 2 ;;
    --resuelta)   resuelta="$2"; shift 2 ;;
    --resolucion) resolucion="$2"; shift 2 ;;
    --json)       json=1; shift ;;
    -h|--help)    sed -n '2,19p' "$0"; exit 0 ;;
    -*)           echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *)            n="$1"; shift ;;
  esac
done
[[ "$n" =~ ^[0-9]+$ ]] || { echo "Falta <n> (entero, clave de cruce.n)" >&2; exit 2; }
[[ -z "$merge"    || "$merge"    =~ ^[01]$ ]] || { echo "--merge debe ser 0|1" >&2; exit 2; }
[[ -z "$resuelta" || "$resuelta" =~ ^[01]$ ]] || { echo "--resuelta debe ser 0|1" >&2; exit 2; }
[[ -n "$merge$resuelta$resolucion" ]] || { echo "Nada que hacer: pasa --merge, --resuelta o --resolucion" >&2; exit 2; }

p="$(require_db "$DB")"
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

row="$(sqlite_ro "$p" "SELECT veredicto||'|'||confianza||'|'||resuelta||'|'||coalesce(ce_id,'') FROM cruce WHERE n=$n")"
[[ -n "$row" ]] || { echo "No existe la fila n=$n en cruce" >&2; exit 1; }
IFS='|' read -r ver conf res ce <<<"$row"

if [[ -n "$merge" && "$merge" == 1 ]]; then
  [[ "$ver" == "igual" && "$conf" == "alta" ]] || { echo "Solo las filas igual+alta se marcan para merge (n=$n es $ver+$conf)" >&2; exit 1; }
  [[ "$res" == 0 ]] || { echo "La fila n=$n ya está resuelta; no admite marca de merge" >&2; exit 1; }
  if [[ -n "$ce" ]]; then
    dup="$(sqlite_ro "$p" "SELECT group_concat(n,', ') FROM cruce WHERE ce_id='$(esc "$ce")' AND merge=1 AND n<>$n")"
    [[ -z "$dup" ]] || {
      echo "La tarea del cerebro $ce ya está marcada para merge en n=$dup — la plataforma PM la duplica." >&2
      echo "Se mezcla UNA sola vez: desmarcá n=$dup si preferís mezclar por n=$n." >&2
      exit 1; }
  fi
fi

sets=()
[[ -n "$merge"      ]] && sets+=("merge=$merge")
[[ -n "$resolucion" ]] && sets+=("resolucion='$(esc "$resolucion")'")
if [[ -n "$resuelta" ]]; then
  if [[ "$resuelta" == 1 ]]; then
    sets+=("resuelta=1" "resuelta_en=strftime('%Y-%m-%dT%H:%M:%SZ','now')")
  else
    sets+=("resuelta=0" "resuelta_en=NULL" "resolucion=NULL")
  fi
fi
IFS=, ; setsql="${sets[*]}" ; unset IFS

sqlite_rw "$p" "BEGIN; UPDATE cruce SET $setsql WHERE n=$n; COMMIT;"

after="$(sqlite_ro "$p" -json "SELECT n, merge, resuelta, resolucion, resuelta_en, veredicto, confianza FROM cruce WHERE n=$n" | sed 's/^\[//;s/\]$//')"
if [[ "$json" == 1 || "$FORMAT" == json ]]; then
  printf '{"ok":true,"row":%s}\n' "$after"
else
  echo "OK n=$n → $after"
fi
