#!/usr/bin/env bash
# Edit a task's IO (inputs/outputs): retype them to their semantic io_type and
# concrete artifact_type, rename, toggle required, or add/remove rows. WRITE
# operation (psql_rw), single transaction, --dry-run rolls back. Prints the
# affected row before/after. Emits a small JSON result (--json) carrying task_id
# so callers (e.g. the viz editor) know what to re-render.
#
# One operation per call. Pick a mode:
#
#   UPDATE one IO row:
#     update_task_io.sh --io <io_id> [--title T] [--io-type NAME] \
#                       [--artifact NAME] [--required true|false]
#       --io-type / --artifact accept the io_types/artifact_types `name` OR
#       `display_name`. Pass an empty value ('') to clear (set NULL).
#
#   ADD a blank IO row (title defaults to "Nuevo input"/"Nuevo output"):
#     update_task_io.sh --add input|output --task <task_id|prefix> [--title T]
#
#   DELETE one IO row:
#     update_task_io.sh --delete --io <io_id> [--cascade]
#       Deleting an OUTPUT that still has acceptance criteria is blocked unless
#       --cascade is given (criteria are FK ON DELETE CASCADE).
#
# Common: [--dry-run] rolls back · [--json] machine output · [-h] help.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

io="" task="" add="" del="" cascade="" dry=""
declare -A set_provided=()
title="" iotype="" artifact="" required=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --io)       io="${2//\'/}"; shift 2 ;;
    --task)     task="${2//\'/}"; shift 2 ;;
    --add)      add="$2"; shift 2 ;;
    --delete)   del=1; shift ;;
    --cascade)  cascade=1; shift ;;
    --title)    title="$2"; set_provided[title]=1; shift 2 ;;
    --io-type)  iotype="$2"; set_provided[iotype]=1; shift 2 ;;
    --artifact) artifact="$2"; set_provided[artifact]=1; shift 2 ;;
    --required) required="$2"; set_provided[required]=1; shift 2 ;;
    --ref-clear) set_provided[refclear]=1; shift ;;
    --dry-run)  dry=1; shift ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

is_json() { [[ "$FORMAT" == "json" ]]; }
# Run a writable psql; in --json mode keep stdout pure JSON by sending psql's
# human table/echo output to stderr.
rw() { if is_json; then psql_rw "$@" 1>&2; else psql_rw "$@"; fi; }
fail() { # message
  if is_json; then printf '{"ok":false,"error":%s}\n' "$(json_str "$1")"; else echo "$1" >&2; fi
  exit 1
}
json_str() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }

# Resolve an io_type/artifact_type reference (id, name or display_name) to its
# id. Echoes the id, or empty if no match. Caller decides if empty is an error.
resolve_type() { # <table> <ref>
  local tbl="$1" ref="${2//\'/\'\'}"
  psql_ro -t -A -c "SELECT id FROM ikigaigm.$tbl WHERE id::text='$ref' OR name='$ref' OR display_name='$ref' LIMIT 1;"
}

# Which table does an io_id live in? Echoes 'input'|'output' (empty if neither).
io_kind() { # <io_id>
  local id="${1//\'/\'\'}"
  psql_ro -t -A -c "
    SELECT 'input'  WHERE EXISTS (SELECT 1 FROM ikigaigm.task_inputs  WHERE id='$id')
    UNION ALL
    SELECT 'output' WHERE EXISTS (SELECT 1 FROM ikigaigm.task_outputs WHERE id='$id')
    LIMIT 1;"
}

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"

# ── ADD ────────────────────────────────────────────────────────────────────
if [[ -n "$add" ]]; then
  [[ "$add" == "input" || "$add" == "output" ]] || fail "--add must be 'input' or 'output'"
  [[ -n "$task" ]] || fail "--add requires --task <task_id|prefix>"
  tid="$(psql_ro -t -A -c "SELECT id FROM ikigaigm.tasks WHERE id::text LIKE '${task//\'/}%' LIMIT 1;")"
  [[ -n "$tid" ]] || fail "No task matches: $task"
  tbl="task_${add}s"
  [[ -n "$title" ]] || title="Nuevo ${add}"
  out="$(psql_rw -t -A -v tid="$tid" -v title="$title" <<SQL
BEGIN;
INSERT INTO ikigaigm.$tbl (task_id, title, is_required, position)
SELECT :'tid', :'title', true,
       coalesce((SELECT max(position)+1 FROM ikigaigm.$tbl WHERE task_id=:'tid'), 0)
RETURNING id;
$end;
SQL
)"
  newid="$(printf '%s\n' "$out" | grep -Eio '[0-9a-f]{8}-[0-9a-f-]{27}' | head -1)"
  if is_json; then
    printf '{"ok":true,"action":"add","kind":"%s","io_id":"%s","task_id":"%s"%s}\n' \
      "$add" "$newid" "$tid" "$([[ -n "$dry" ]] && echo ',"dry_run":true')"
  else
    echo "Added $add $newid to task ${tid:0:8} (title: \"$title\")"
    [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
  fi
  exit 0
fi

# ── DELETE / UPDATE both need --io ───────────────────────────────────────────
[[ -n "$io" ]] || fail "specify --io <io_id> (update/delete) or --add (add)"
kind="$(io_kind "$io")"
[[ -n "$kind" ]] || fail "No IO row matches: $io"
tbl="task_${kind}s"
tid="$(psql_ro -t -A -c "SELECT task_id FROM ikigaigm.$tbl WHERE id='${io//\'/\'\'}';")"

# ── DELETE ───────────────────────────────────────────────────────────────────
if [[ -n "$del" ]]; then
  if [[ "$kind" == "output" && -z "$cascade" ]]; then
    nc="$(psql_ro -t -A -c "SELECT count(*) FROM ikigaigm.task_acceptance_criteria WHERE output_id='${io//\'/\'\'}';")"
    [[ "${nc:-0}" -gt 0 ]] && fail "Output has $nc acceptance criterion(s); pass --cascade to delete them too."
  fi
  rw -v io="$io" <<SQL
BEGIN;
\echo '--- before ---'
SELECT id, title FROM ikigaigm.$tbl WHERE id=:'io';
DELETE FROM ikigaigm.$tbl WHERE id=:'io';
$end;
SQL
  if is_json; then
    printf '{"ok":true,"action":"delete","kind":"%s","io_id":"%s","task_id":"%s"%s}\n' \
      "$kind" "$io" "$tid" "$([[ -n "$dry" ]] && echo ',"dry_run":true')"
  else
    echo "Deleted $kind $io"; [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
  fi
  exit 0
fi

# ── UPDATE ───────────────────────────────────────────────────────────────────
[[ ${#set_provided[@]} -gt 0 ]] || fail "nothing to update; pass --title/--io-type/--artifact/--required"

# Build SET clause + psql vars. Names/columns are controlled; values go via -v.
sets=(); declare -a vargs=()
if [[ -n "${set_provided[title]:-}" ]]; then
  [[ -n "$title" ]] || fail "title cannot be empty"
  sets+=("title = :'v_title'"); vargs+=(-v "v_title=$title")
fi
if [[ -n "${set_provided[iotype]:-}" ]]; then
  if [[ -z "$iotype" ]]; then sets+=("io_type_id = NULL")
  else
    iotid="$(resolve_type io_types "$iotype")"
    [[ -n "$iotid" ]] || fail "Unknown io_type: $iotype"
    sets+=("io_type_id = :'v_iot'"); vargs+=(-v "v_iot=$iotid")
  fi
fi
if [[ -n "${set_provided[artifact]:-}" ]]; then
  if [[ -z "$artifact" ]]; then sets+=("artifact_type_id = NULL")
  else
    atid="$(resolve_type artifact_types "$artifact")"
    [[ -n "$atid" ]] || fail "Unknown artifact_type: $artifact"
    sets+=("artifact_type_id = :'v_at'"); vargs+=(-v "v_at=$atid")
  fi
fi
if [[ -n "${set_provided[required]:-}" ]]; then
  case "$required" in
    true|false) sets+=("is_required = $required") ;;
    *) fail "--required must be true or false" ;;
  esac
fi
if [[ -n "${set_provided[refclear]:-}" ]]; then
  # Clear the binding locator (the reference jsonb), column depends on kind.
  [[ "$kind" == "output" ]] && sets+=("deliverable_reference = '{}'::jsonb") || sets+=("artifact_reference = '{}'::jsonb")
fi

setclause="$(IFS=,; echo "${sets[*]}")"
detail="SELECT i.id, i.title, it.display_name AS io_type, at.display_name AS artifact, i.is_required
  FROM ikigaigm.$tbl i
  LEFT JOIN ikigaigm.io_types it ON it.id=i.io_type_id
  LEFT JOIN ikigaigm.artifact_types at ON at.id=i.artifact_type_id
  WHERE i.id=:'io'"

rw "${vargs[@]}" -v io="$io" <<SQL
BEGIN;
\echo '--- before ---'
$detail;
UPDATE ikigaigm.$tbl SET $setclause, updated_at = now() WHERE id=:'io';
\echo '--- after ---'
$detail;
$end;
SQL

if is_json; then
  printf '{"ok":true,"action":"update","kind":"%s","io_id":"%s","task_id":"%s"%s}\n' \
    "$kind" "$io" "$tid" "$([[ -n "$dry" ]] && echo ',"dry_run":true')"
else
  [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
fi
