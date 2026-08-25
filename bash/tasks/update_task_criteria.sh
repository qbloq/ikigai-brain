#!/usr/bin/env bash
# Edit the acceptance criteria of a task's OUTPUT: reword them, change how they
# get verified, toggle required, or add/remove rows. The twin of
# update_task_io.sh for the other half of the work contract. WRITE operation
# (psql_rw), single transaction, --dry-run rolls back. Prints the affected row
# before/after and emits a small JSON result (--json) carrying task_id so
# callers know what to re-render.
#
# A criterion hangs off an OUTPUT (task_acceptance_criteria.output_id), never
# off the task — that is why every mode addresses either a criterion or the
# output it belongs to.
#
# One operation per call. Pick a mode:
#
#   UPDATE one criterion:
#     update_task_criteria.sh --crit <crit_id|prefix> [--text T] \
#         [--method llm|manual|automated|test|attested] \
#         [--required true|false] [--category C]
#       --category takes '' to clear (it is free text, no catalog).
#
#   ADD a criterion to an output:
#     update_task_criteria.sh --add --output <output_id|prefix> --text T \
#         [--method M] [--required true|false] [--category C]
#
#   DELETE one criterion:
#     update_task_criteria.sh --delete --crit <crit_id|prefix> [--cascade]
#       Blocked when the criterion already has attestations (a human confirmed
#       it over WhatsApp) unless --cascade — those rows are FK ON DELETE CASCADE
#       and deleting them erases the evidence, not just the criterion.
#
# NOT here on purpose: is_met / verified_* are verification STATE, not the
# contract. They are earned by attestation, never typed by hand.
#
# Common: [--dry-run] rolls back · [--json] machine output · [-h] help.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# The DB check constraint task_acceptance_criteria_verification_method_check.
METHODS="llm manual automated test attested"

crit="" output="" add="" del="" cascade="" dry=""
provided=""   # banderas separadas por espacio (bash 3.2: sin arrays asociativos)
has() { [[ " $provided " == *" $1 "* ]]; }
text="" method="" required="" category=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --crit)     crit="${2//\'/}"; shift 2 ;;
    --output)   output="${2//\'/}"; shift 2 ;;
    --add)      add=1; shift ;;
    --delete)   del=1; shift ;;
    --cascade)  cascade=1; shift ;;
    --text)     text="$2"; provided="$provided text"; shift 2 ;;
    --method)   method="$2"; provided="$provided method"; shift 2 ;;
    --required) required="$2"; provided="$provided required"; shift 2 ;;
    --category) category="$2"; provided="$provided category"; shift 2 ;;
    --dry-run)  dry=1; shift ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

is_json() { [[ "$FORMAT" == "json" ]]; }
# Run a writable psql; in --json mode keep stdout pure JSON by sending psql's
# human table/echo output to stderr.
rw() { if is_json; then psql_rw "$@" 1>&2; else psql_rw "$@"; fi; }
json_str() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' -- "$1"; }
fail() { # message
  if is_json; then printf '{"ok":false,"error":%s}\n' "$(json_str "$1")"; else echo "$1" >&2; fi
  exit 1
}

# Resolve an id PREFIX against one table -> full id. Unlike update_task_io.sh
# (whose ids come from the viz, always complete) this script is driven from the
# conversation, where ids are typed by hand — so a prefix is the normal input
# and ambiguity has to be an error, never a silent first-match.
resolve_id() { # <table> <prefix> <label>
  local tbl="$1" pfx="${2//\'/\'\'}" label="$3" rows n
  rows="$(psql_ro -t -A -c "SELECT id FROM $tbl WHERE id::text LIKE '${pfx}%';")"
  [[ -n "$rows" ]] || fail "No $label matches: $2"
  n="$(printf '%s\n' "$rows" | grep -c .)"
  [[ "$n" -gt 1 ]] && fail "'$2' is ambiguous ($n $label rows match); pass a longer prefix."
  printf '%s\n' "$rows"
}

check_method() {
  [[ " $METHODS " == *" $1 "* ]] || fail "--method must be one of: $METHODS"
}

# The task a criterion/output belongs to — every JSON result carries it.
task_of_output() { # <output_id>
  psql_ro -t -A -c "SELECT task_id FROM task_outputs WHERE id='${1//\'/\'\'}';"
}

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"

# The before/after projection, shared by add and update.
detail_sql() { # <criterion_id psql var name>
  cat <<SQL
SELECT c.id, c.criterion, c.verification_method AS method, c.criterion_category AS category,
       c.is_required, c.is_met, o.title AS output
  FROM task_acceptance_criteria c
  JOIN task_outputs o ON o.id=c.output_id
  WHERE c.id=:'$1'
SQL
}

# ── ADD ──────────────────────────────────────────────────────────────────────
if [[ -n "$add" ]]; then
  [[ -n "$output" ]] || fail "--add requires --output <output_id|prefix>"
  [[ -n "$text" ]] || fail "--add requires --text \"the criterion\""
  oid="$(resolve_id task_outputs "$output" output)"
  tid="$(task_of_output "$oid")"
  if has method; then check_method "$method"; else method="manual"; fi
  req=true
  case "${required:-true}" in
    true) req=true ;;
    false) req=false ;;
    *) fail "--required must be true or false" ;;
  esac
  out="$(psql_rw -t -A -v oid="$oid" -v text="$text" -v method="$method" -v cat="${category:-}" <<SQL
BEGIN;
INSERT INTO task_acceptance_criteria (output_id, criterion, verification_method, criterion_category, is_required, position)
SELECT :'oid', :'text', :'method', nullif(:'cat',''), $req,
       coalesce((SELECT max(position)+1 FROM task_acceptance_criteria WHERE output_id=:'oid'), 0)
RETURNING id;
$end;
SQL
)"
  newid="$(printf '%s\n' "$out" | grep -Eio '[0-9a-f]{8}-[0-9a-f-]{27}' | head -1)"
  if is_json; then
    printf '{"ok":true,"action":"add","criterion_id":"%s","output_id":"%s","task_id":"%s"%s}\n' \
      "$newid" "$oid" "$tid" "$([[ -n "$dry" ]] && echo ',"dry_run":true')"
  else
    echo "Added criterion ${newid:0:8} to output ${oid:0:8} (task ${tid:0:8}, method: $method)"
    echo "  \"$text\""
    [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
  fi
  exit 0
fi

# ── DELETE / UPDATE both need --crit ─────────────────────────────────────────
[[ -n "$crit" ]] || fail "specify --crit <crit_id|prefix> (update/delete) or --add --output <id> (add)"
cid="$(resolve_id task_acceptance_criteria "$crit" criterion)"
oid="$(psql_ro -t -A -c "SELECT output_id FROM task_acceptance_criteria WHERE id='$cid';")"
tid="$(task_of_output "$oid")"

# ── DELETE ───────────────────────────────────────────────────────────────────
if [[ -n "$del" ]]; then
  if [[ -z "$cascade" ]]; then
    na="$(psql_ro -t -A -c "SELECT count(*) FROM task_attestations WHERE criterion_id='$cid';")"
    [[ "${na:-0}" -gt 0 ]] && fail "Criterion has $na attestation(s) — deleting it erases that evidence; pass --cascade to delete them too."
  fi
  rw -v cid="$cid" <<SQL
BEGIN;
\echo '--- before ---'
$(detail_sql cid);
DELETE FROM task_acceptance_criteria WHERE id=:'cid';
$end;
SQL
  if is_json; then
    printf '{"ok":true,"action":"delete","criterion_id":"%s","output_id":"%s","task_id":"%s"%s}\n' \
      "$cid" "$oid" "$tid" "$([[ -n "$dry" ]] && echo ',"dry_run":true')"
  else
    echo "Deleted criterion $cid"; [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
  fi
  exit 0
fi

# ── UPDATE ───────────────────────────────────────────────────────────────────
[[ -n "$provided" ]] || fail "nothing to update; pass --text/--method/--required/--category"

# Build SET clause + psql vars. Columns are controlled; values go via -v.
sets=(); declare -a vargs=()
if has text; then
  [[ -n "$text" ]] || fail "criterion text cannot be empty"
  sets+=("criterion = :'v_text'"); vargs+=(-v "v_text=$text")
fi
if has method; then
  check_method "$method"
  sets+=("verification_method = :'v_method'"); vargs+=(-v "v_method=$method")
fi
if has required; then
  case "$required" in
    true|false) sets+=("is_required = $required") ;;
    *) fail "--required must be true or false" ;;
  esac
fi
if has category; then
  # Free text, no catalog behind it: '' clears.
  sets+=("criterion_category = nullif(:'v_cat','')"); vargs+=(-v "v_cat=$category")
fi

setclause="$(IFS=,; echo "${sets[*]}")"
rw ${vargs[@]+"${vargs[@]}"} -v cid="$cid" <<SQL
BEGIN;
\echo '--- before ---'
$(detail_sql cid);
UPDATE task_acceptance_criteria SET $setclause, updated_at = now() WHERE id=:'cid';
\echo '--- after ---'
$(detail_sql cid);
$end;
SQL

if is_json; then
  printf '{"ok":true,"action":"update","criterion_id":"%s","output_id":"%s","task_id":"%s"%s}\n' \
    "$cid" "$oid" "$tid" "$([[ -n "$dry" ]] && echo ',"dry_run":true')"
else
  [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)" || true
fi
