#!/usr/bin/env bash
# permiso_ui.sh <slug> --rol <Rol> | --user <email>
#               [--identidad k=v]... | --sin-identidad
#               [--revocar] | [--listar] | [--visitas]  [--dry-run] [--json]
# Permisos de un despliegue publicado.        [WRITE remoto]
#   sin flags de identidad  → NULL  (hereda la plantilla del despliegue)
#   --sin-identidad         → '{}'  (anula la plantilla: ve todo — p.ej. Director)
#   --identidad k=v         → json explícito (excepciones)
#   --json     con insert/--revocar: imprime {"slug","accion","rol","user",
#              "params_identidad"} en vez del echo plano. Ignorado en
#              --dry-run (siempre imprime el SQL, con o sin --json).
#   --listar / --visitas SIEMPRE emiten JSON (no miran --json ni --dry-run).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$REPO_ROOT/bash/lib/common.sh"   # psql_ro para resolver email → users.id

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -12; exit "${1:-0}"; }

SLUG="" ROL="" EMAIL="" REVOCAR=0 LISTAR=0 VISITAS=0 SIN_IDENT=0 DRY=0 JSON=0
# Mapa clave→valor de --identidad (bash 3.2: sin arrays asociativos — arrays
# paralelos + búsqueda lineal; una clave repetida pisa el valor anterior).
IDENT_K=(); IDENT_V=()
ident_set() { local i; for i in "${!IDENT_K[@]}"; do [[ "${IDENT_K[$i]}" == "$1" ]] && { IDENT_V[$i]="$2"; return; }; done; IDENT_K+=("$1"); IDENT_V+=("$2"); }
while [[ $# -gt 0 ]]; do case "$1" in
  --rol) ROL="$2"; shift 2;;
  --user) EMAIL="$2"; shift 2;;
  --identidad) k="${2%%=*}"; ident_set "$k" "${2#*=}"; shift 2;;
  --sin-identidad) SIN_IDENT=1; shift;;
  --revocar) REVOCAR=1; shift;;
  --listar) LISTAR=1; shift;;
  --visitas) VISITAS=1; shift;;
  --dry-run) DRY=1; shift;;
  --json) JSON=1; shift;;
  -h|--help) usage;;
  -*) echo "Flag desconocido: $1" >&2; usage 2;;
  *) SLUG="$1"; shift;;
esac; done
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || { echo "Slug inválido: '$SLUG'" >&2; exit 2; }

if [[ $LISTAR -eq 1 ]]; then
  printf 'SELECT id, coalesce(rol, "user:" || user_id) sujeto, coalesce(params_identidad, "(hereda)") identidad,
          creado_at, coalesce(revocado_at, "") revocado FROM permisos WHERE slug=%s;' "$(sql_lit "$SLUG")" \
    | remote_sql -json; exit 0
fi
if [[ $VISITAS -eq 1 ]]; then
  printf 'SELECT email, count(*) n, max(ts) ultima FROM visitas WHERE slug=%s GROUP BY email ORDER BY ultima DESC LIMIT 50;' \
    "$(sql_lit "$SLUG")" | remote_sql -json; exit 0
fi

[[ -n "$ROL" || -n "$EMAIL" ]] || usage 2
[[ -n "$ROL" && -n "$EMAIL" ]] && { echo "Usa --rol O --user, no ambos" >&2; exit 2; }

USER_ID=""
if [[ -n "$EMAIL" ]]; then
  USER_ID="$(psql_ro -Atc "select id from users where lower(email)=lower('${EMAIL//\'/\'\'}')")"
  [[ -n "$USER_ID" ]] || { echo "No existe user con email '$EMAIL' (¿crear con /crear-usuario?)" >&2; exit 1; }
fi
if [[ -n "$ROL" ]]; then
  HAY="$(psql_ro -Atc "select count(*) from team_roles where name='${ROL//\'/\'\'}'")"
  [[ "$HAY" != "0" ]] || echo "AVISO: el rol '$ROL' no existe en team_roles — nadie lo matcheará." >&2
fi

SUJETO_SQL="$([[ -n "$ROL" ]] && printf 'rol=%s' "$(sql_lit "$ROL")" || printf 'user_id=%s' "$(sql_lit "$USER_ID")")"

# IDENT_MODE/IDENT_JSON_TXT quedan definidos también en la rama --revocar
# (vacíos, sin usarse) para que el bloque --json de abajo pueda leerlos sin
# pisar `set -u`.
IDENT_MODE="hereda" IDENT_JSON_TXT=""
if [[ $REVOCAR -eq 1 ]]; then
  SQL="UPDATE permisos SET revocado_at=datetime('now') WHERE slug=$(sql_lit "$SLUG") AND $SUJETO_SQL AND revocado_at IS NULL;"
else
  [[ $SIN_IDENT -eq 1 ]] && { IDENT_MODE="vacio"; IDENT_JSON_TXT="{}"; }
  if [[ ${#IDENT_K[@]} -gt 0 ]]; then
    IDENT_MODE="explicito"
    PARES=(); for i in "${!IDENT_K[@]}"; do PARES+=("${IDENT_K[$i]}=${IDENT_V[$i]}"); done
    IDENT_JSON_TXT="$(node -e '
      const out = {}; for (const kv of process.argv.slice(1)) { const i = kv.indexOf("=");
        out[kv.slice(0, i)] = kv.slice(i + 1); } console.log(JSON.stringify(out));' "${PARES[@]}")"
  fi
  IDENT_SQL="NULL"; [[ "$IDENT_MODE" != "hereda" ]] && IDENT_SQL="$(sql_lit "$IDENT_JSON_TXT")"
  SQL="INSERT INTO permisos (slug, rol, user_id, params_identidad)
       VALUES ($(sql_lit "$SLUG"), $([[ -n "$ROL" ]] && sql_lit "$ROL" || echo NULL),
               $([[ -n "$USER_ID" ]] && sql_lit "$USER_ID" || echo NULL), $IDENT_SQL);"
fi

# --dry-run sale ANTES de tocar el remoto, con o sin --json: el SQL es la
# vista honesta del preview, no vale la pena fingir un objeto JSON de un
# escrito que no ocurrió.
[[ $DRY -eq 1 ]] && { echo "[dry-run] $SQL"; exit 0; }
ensure_schema; printf '%s\n' "$SQL" | remote_sql

ACCION="permiso"; [[ $REVOCAR -eq 1 ]] && ACCION="revocado"
if [[ $JSON -eq 1 ]]; then
  node -e '
    const [,, slug, accion, rol, user, mode, identTxt] = process.argv;
    const out = { slug, accion, rol: rol || null, user: user || null };
    if (accion !== "revocado") {
      out.params_identidad = mode === "hereda" ? "(hereda)" : JSON.parse(identTxt || "{}");
    }
    console.log(JSON.stringify(out));
  ' "$SLUG" "$ACCION" "$ROL" "$EMAIL" "$IDENT_MODE" "$IDENT_JSON_TXT"
else
  echo "Hecho: $([[ $REVOCAR -eq 1 ]] && echo revocado || echo permiso creado) — '$SLUG' ${ROL:+rol=$ROL}${EMAIL:+user=$EMAIL}"
fi
