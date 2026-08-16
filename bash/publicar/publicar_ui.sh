#!/usr/bin/env bash
# publicar_ui.sh <spec-id> --slug <slug> [--identidad k=v]... [--fijar k=v]...
#                [--archivar] [--forzar] [--dry-run] [--json]   [WRITE remoto]
# Publica (o re-publica: generación+1) un spec del viz como despliegue del
# publicador. El spec viaja CONGELADO (snapshot); la identidad es la plantilla
# {"k":"$name|$email|$user_id|literal"}. --archivar despublica (sella, no borra).
# --forzar salta la sonda de render (NO la negativa por `pattern`).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -7; exit "${1:-0}"; }

SPEC_ID="" SLUG="" DRY=0 JSON=0 ARCHIVAR=0 FORZAR=0
declare -A IDENT=() FIJAR=()
while [[ $# -gt 0 ]]; do case "$1" in
  --slug) SLUG="$2"; shift 2;;
  --identidad) k="${2%%=*}"; IDENT[$k]="${2#*=}"; shift 2;;
  --fijar) k="${2%%=*}"; FIJAR[$k]="${2#*=}"; shift 2;;
  --archivar) ARCHIVAR=1; shift;;
  --forzar) FORZAR=1; shift;;
  --dry-run) DRY=1; shift;;
  --json) JSON=1; shift;;
  -h|--help) usage;;
  -*) echo "Flag desconocido: $1" >&2; usage 2;;
  *) SPEC_ID="$1"; shift;;
esac; done
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || { echo "Slug inválido (a-z 0-9 -): '$SLUG'" >&2; exit 2; }

if [[ $ARCHIVAR -eq 1 ]]; then
  SQL="UPDATE despliegues SET archivado_at=datetime('now') WHERE slug=$(sql_lit "$SLUG") AND archivado_at IS NULL;"
  [[ $DRY -eq 1 ]] && { echo "[dry-run] $SQL"; exit 0; }
  ensure_schema; printf '%s\n' "$SQL" | remote_sql
  echo "Despliegue '$SLUG' archivado."; exit 0
fi

[[ -n "$SPEC_ID" ]] || usage 2
SPEC_JSON="$(spec_local "$SPEC_ID")"
validar_spec "$SPEC_JSON"
COMPONENT="$(node -pe 'JSON.parse(process.argv[1]).component || ""' "$SPEC_JSON")"
SOURCE="$(node -pe 'JSON.parse(process.argv[1]).source || ""' "$SPEC_JSON")"

# --- guarda 1: los specs v2 (por `pattern`) no son publicables --------------
# Un patrón compone bloques ruteados y el publicador NO monta /c/ por
# construcción (no importa lib/actions.js). Publicarlo da una página que
# renderiza y muere al primer clic. Ni --forzar la salta: no es un falso
# positivo, es una superficie que ahí no existe.
if [[ "$(node -pe 'JSON.parse(process.argv[1]).pattern ? "1" : "0"' "$SPEC_JSON")" == "1" ]]; then
  echo "ERROR: '$SPEC_ID' es un spec v2 (tiene 'pattern'): compone bloques ruteados bajo /c/," >&2
  echo "       y el publicador no sirve esas rutas. No es publicable." >&2
  exit 1
fi

# --- guarda 2 (M5): las variables de identidad son un set cerrado -----------
# Un '$closer' mal escrito no explota: resolverIdentidad lo trata como literal
# y fuerza la cadena "$closer" como filtro. Se detecta AQUÍ, no en producción.
for k in "${!IDENT[@]}"; do
  v="${IDENT[$k]}"
  if [[ "$v" == \$* && "$v" != "\$name" && "$v" != "\$email" && "$v" != "\$user_id" ]]; then
    echo "ERROR: identidad '$k=$v': variable desconocida. Solo existen \$name, \$email, \$user_id." >&2
    echo "       (un literal que empiece por '\$' no es representable — usá otro valor)" >&2
    exit 2
  fi
done

# json de identidad y fijos desde los pares k=v
to_json() { node -e '
  const out = {}; for (const kv of process.argv.slice(1)) { const i = kv.indexOf("=");
    out[kv.slice(0, i)] = kv.slice(i + 1); } console.log(JSON.stringify(out));' "$@"; }
IDENT_ARGS=(); for k in "${!IDENT[@]}"; do IDENT_ARGS+=("$k=${IDENT[$k]}"); done
FIJAR_ARGS=(); for k in "${!FIJAR[@]}"; do FIJAR_ARGS+=("$k=${FIJAR[$k]}"); done
IDENT_JSON="$([[ ${#IDENT_ARGS[@]} -gt 0 ]] && to_json "${IDENT_ARGS[@]}" || echo "")"
FIJAR_JSON="$([[ ${#FIJAR_ARGS[@]} -gt 0 ]] && to_json "${FIJAR_ARGS[@]}" || echo "{}")"

# --dry-run sale ANTES de tocar el remoto (ensure_schema/PREV): el servidor
# puede no existir todavía. Se imprime el INSERT con el spec congelado y
# generacion=? — el número real depende del max(generacion) remoto.
if [[ $DRY -eq 1 ]]; then
  SQL="INSERT INTO despliegues (slug, codigo_corto, spec_id, spec_json, component, source, params_fijos, identidad, generacion)
VALUES ($(sql_lit "$SLUG"), <codigo_corto existente o nuevo>, $(sql_lit "$SPEC_ID"), $(sql_lit "$SPEC_JSON"),
        $(sql_lit "$COMPONENT"), $(sql_lit "$SOURCE"), $(sql_lit "$FIJAR_JSON"),
        $([[ -n "$IDENT_JSON" ]] && sql_lit "$IDENT_JSON" || echo NULL), <generacion=? siguiente>);"
  echo "[dry-run] generacion=? de '$SLUG':"
  echo "$SQL"
  exit 0
fi

# --- guarda 3 (I3): la sonda de render --------------------------------------
# La pregunta que ningún check estático responde: ¿esta página, con ESTE spec,
# emite URLs /c/? Un `component` v1 puede delegar en un patrón por dentro
# (pages/tasks.js lo hace) y quedar igual de roto en el publicador. Así que se
# renderiza de verdad y se lee el HTML. Pega contra la DB real (~1-3 s): es
# barato al publicar, y --dry-run ya salió arriba sin pagarlo.
if [[ $FORZAR -eq 1 ]]; then
  echo "[--forzar] sonda de render saltada." >&2
else
  # stderr aparte de stdout: si el render escupe una advertencia, no debe
  # terminar concatenada al JSON de la sonda (un `[]` contaminado la rompe).
  SONDA_ERR="$(mktemp)"; trap 'rm -f "$SONDA_ERR"' EXIT
  if ! SONDA="$(node -e '
    const root = process.argv[1];
    const spec = JSON.parse(process.argv[2]);
    const { getComponent } = require(root + "/viz/lib/components");
    const page = getComponent(spec.component || "table");
    if (!page || typeof page.render !== "function")
      throw new Error("componente sin render: " + (spec.component || "table"));
    const html = String(page.render(spec) || "");
    const urls = [...new Set((html.match(/[\x27"(]\/c\/[^\x27")\s]*/g) || [])
      .map((u) => u.slice(1)))];
    console.log(JSON.stringify(urls));
  ' "$REPO_ROOT" "$SPEC_JSON" 2>"$SONDA_ERR")"; then
    echo "ERROR: la sonda de render falló — no se publica a ciegas:" >&2
    sed 's/^/       /' "$SONDA_ERR" >&2
    echo "       (si estás seguro de que el spec no usa /c/, repetí con --forzar)" >&2
    exit 1
  fi
  if [[ "$SONDA" != "[]" ]]; then
    echo "ERROR: el render de '$SPEC_ID' emite URLs /c/ — rutas que el publicador NO sirve." >&2
    node -pe 'JSON.parse(process.argv[1]).map(u => "       " + u).join("\n")' "$SONDA" >&2
    echo "       La página quedaría muerta al primer clic. Usá --forzar solo si sabés que no." >&2
    exit 1
  fi
fi

ensure_schema
PREV="$(printf 'SELECT max(generacion) || "|" || codigo_corto FROM despliegues WHERE slug=%s;' "$(sql_lit "$SLUG")" | remote_sql)"
GEN=$(( ${PREV%%|*} + 1 )) 2>/dev/null || GEN=1
[[ -z "$PREV" ]] && GEN=1
CODIGO="${PREV#*|}"; [[ -z "$PREV" ]] && CODIGO="$(codigo_nuevo)"

SQL="INSERT INTO despliegues (slug, codigo_corto, spec_id, spec_json, component, source, params_fijos, identidad, generacion)
VALUES ($(sql_lit "$SLUG"), $(sql_lit "$CODIGO"), $(sql_lit "$SPEC_ID"), $(sql_lit "$SPEC_JSON"),
        $(sql_lit "$COMPONENT"), $(sql_lit "$SOURCE"), $(sql_lit "$FIJAR_JSON"),
        $([[ -n "$IDENT_JSON" ]] && sql_lit "$IDENT_JSON" || echo NULL), $GEN);"

printf '%s\n' "$SQL" | remote_sql

if [[ $JSON -eq 1 ]]; then
  node -e 'console.log(JSON.stringify({slug: process.argv[1], generacion: Number(process.argv[2]),
    codigo: process.argv[3], url: process.argv[4] + "/" + process.argv[1],
    url_corta: process.argv[4] + "/s/" + process.argv[3]}))' "$SLUG" "$GEN" "$CODIGO" "$PUB_URL"
else
  echo "Publicado '$SLUG' (generación $GEN, spec $SPEC_ID)"
  echo "  URL:   $PUB_URL/$SLUG"
  echo "  Corta: $PUB_URL/s/$CODIGO"
  echo "Ahora dale permisos: bash/publicar/permiso_ui.sh $SLUG --rol '<Rol>'"
fi
