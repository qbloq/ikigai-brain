#!/usr/bin/env bash
# Common helpers for bash/ read-only DB scripts.
# Source this from any script: source "$(dirname "$0")/../lib/common.sh"
set -euo pipefail

BASH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BASH_LIB_DIR/../.." && pwd)"

# --- Dependency guard -------------------------------------------------------
# psql es la única dependencia no-estándar de esta capa. El repo puede llevar
# su propio cliente en bin/ (git-ignored, lo puebla el onboarding cuando no
# hay gestor de paquetes) — privado del copiloto, jamás en el PATH global.
export PATH="$REPO_ROOT/bin:$PATH"
command -v psql >/dev/null 2>&1 || {
  echo "Falta psql (el cliente de Postgres) — los scripts de datos lo necesitan." >&2
  echo "  macOS con brew : brew install libpq && brew link --force libpq" >&2
  echo "  macOS sin brew : binarios del cliente en $REPO_ROOT/bin/ (psql + lib/)" >&2
  echo "  Linux          : sudo apt install postgresql-client" >&2
  exit 3
}

# --- Load DATABASE_URL from .env -------------------------------------------
if [[ -z "${DATABASE_URL:-}" && -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi
: "${DATABASE_URL:?DATABASE_URL not set (expected in $REPO_ROOT/.env)}"
# The org's Postgres schema. The genome presupposes NONE — each brain declares
# its own (see cerebro.json / docs: "el cerebro nace conectado, no poblado").
: "${DB_SCHEMA:?DB_SCHEMA not set - the Postgres schema of this org, expected in $REPO_ROOT/.env}"

# --- Connection policy -----------------------------------------------------
# Every connection is read-only, scoped to the org's schema, in the org's tz.
# search_path is the SINGLE point where the schema is bound: SQL in the scripts
# is written unqualified (FROM tasks, not FROM <schema>.tasks) so nothing below
# this line needs to know the org.
TZ_DEFAULT="${BRAIN_TZ:-America/Bogota}"
export PGOPTIONS="-c default_transaction_read_only=on -c search_path=$DB_SCHEMA,public -c timezone=$TZ_DEFAULT"

# --- Output format ---------------------------------------------------------
# Set FORMAT=json (or pass --json, handled by scripts) for machine output.
FORMAT="${FORMAT:-table}"

# psql_ro [args...] : run psql read-only, stop on error, no pager.
psql_ro() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 --pset pager=off "$@"
}

# psql_rw [args...] : run psql with a WRITABLE connection (still scoped to the
# org's schema + tz). Write scripts must opt into this explicitly; reads
# stay read-only by default. Wrap mutations in BEGIN/COMMIT.
psql_rw() {
  PGOPTIONS="-c search_path=$DB_SCHEMA,public -c timezone=$TZ_DEFAULT" \
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 --pset pager=off "$@"
}

# resolve_member <token> : echoes the full team_members.id for an id-prefix or
# a person name fragment. Errors (and lists candidates) on no/ambiguous match.
resolve_member() {
  local tok="$1" esc rows n
  esc="${tok//\'/\'\'}"
  rows="$(psql_ro -t -A -F'|' -c "
    SELECT tm.id,
           trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')) AS member,
           coalesce(tr.name,'?') AS role,
           coalesce(te.name,'?') AS team
    FROM team_members tm
    LEFT JOIN team_roles tr ON tr.id=tm.role_id
    LEFT JOIN teams te ON te.id=tm.team_id
    LEFT JOIN users u ON u.id=tm.user_id
    LEFT JOIN persons p ON p.person_id=u.person_id
    WHERE tm.id::text LIKE '${esc}%'
       OR (coalesce(p.name,'')||' '||coalesce(p.lastname,'')) ILIKE '%${esc}%'
    ORDER BY member")"
  if [[ -z "$rows" ]]; then echo "resolve_member: no match for '$tok'" >&2; return 1; fi
  n="$(printf '%s\n' "$rows" | grep -c .)"
  if [[ "$n" -gt 1 ]]; then
    { echo "resolve_member: '$tok' is ambiguous ($n matches):"
      printf '%s\n' "$rows" | awk -F'|' '{printf "   %s  %-24s %-16s %s\n", substr($1,1,8), $2, $3, $4}'
      echo "Refine the name or pass an id prefix."; } >&2
    return 1
  fi
  printf '%s\n' "$rows" | cut -d'|' -f1
}

# emit "<SELECT without trailing semicolon>"
# Renders as an aligned table, or as a JSON array when FORMAT=json.
emit() {
  local sql="$1"
  if [[ "$FORMAT" == "json" ]]; then
    psql_ro -t -A -c "SELECT coalesce(json_agg(row_to_json(_q)), '[]'::json) FROM ($sql) _q;"
  else
    psql_ro -c "$sql;"
  fi
}

# Reusable SQL scalar subquery: resolves tasks.assignee (uuid[]) -> names.
# References the outer table aliased as `t`.
ASSIGNEES_SQL="(SELECT string_agg(nullif(trim(coalesce(p.name,'') || ' ' || coalesce(p.lastname,'')), ''), ', ')
  FROM unnest(t.assignee) AS aid
  JOIN team_members tm ON tm.id = aid
  LEFT JOIN users u ON u.id = tm.user_id
  LEFT JOIN persons p ON p.person_id = u.person_id)"

# Reusable SQL scalar subquery: resolves tasks.assignee (uuid[]) -> role names.
# References the outer table aliased as `t`.
ROLES_SQL="(SELECT string_agg(DISTINCT tr.name, ', ')
  FROM unnest(t.assignee) AS aid
  JOIN team_members tm ON tm.id = aid
  LEFT JOIN team_roles tr ON tr.id = tm.role_id)"

# Standard task listing. Args: <where> [order] [limit]
tasks_select() {
  local where="${1:-true}"
  local order="${2:-t.due_date NULLS LAST, t.priority DESC}"
  local limit="${3:-}"
  local lim=""
  [[ -n "$limit" ]] && lim="LIMIT $limit"
  cat <<SQL
SELECT left(t.id::text, 8)               AS id,
       t.title,
       t.status::text                    AS status,
       t.priority::text                  AS priority,
       to_char(t.due_date, 'YYYY-MM-DD') AS due,
       pr.name                           AS project,
       $ASSIGNEES_SQL                    AS assignees,
       t.source_type                     AS source_type
FROM tasks t
LEFT JOIN projects pr ON pr.id = t.project_id
WHERE $where
ORDER BY $order
$lim
SQL
}

# Open (not done) predicate, reused by due/overdue queries.
OPEN_PRED="t.status NOT IN ('completed','cancelled') AND coalesce(t.is_completed,false) = false"

# Resolve a project name fragment to an id (echoes id or empty).
resolve_project() {
  local frag="$1"
  psql_ro -t -A -c "SELECT id FROM projects WHERE name ILIKE '%${frag//\'/\'\'}%' LIMIT 1;"
}
