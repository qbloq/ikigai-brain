#!/usr/bin/env bash
# group_history.sh — LEER el historial de un grupo ya sincronizado.
#
# El gemelo de lectura de group_sync.sh: aquel escribe y este NUNCA. La conexión
# es `sqlite_ro` (el motor rechaza escrituras), y la separación es a propósito —
# consultar no debe poder alterar la copia.
#
# POR QUÉ EXISTE, SI YA ESTÁ db_query.sh
# Porque este dominio tiene tres trampas que un SELECT a mano vuelve a pisar:
#
#   1. LOS ACENTOS. «Vásquez» viaja con acento COMBINANTE: `texto LIKE
#      '%Marulanda Vás%'` devuelve 0 y `texto_norm LIKE '%marulanda vas%'`
#      devuelve 3. Buscar sobre `texto` da falsos negativos silenciosos — ya
#      nos hizo creer que una oportunidad había desaparecido del espejo.
#      --buscar siempre normaliza la aguja y busca en texto_norm.
#   2. LA FRESCURA. Una búsqueda que da cero no distingue «no existe» de «la
#      copia está vieja». Se avisa la edad del último sync en stderr, y se
#      grita si pasó de un día.
#   3. LOS TELÉFONOS. `numero` es el LID de WhatsApp, NO el teléfono. Buscar
#      un número ahí no encuentra nada; los teléfonos viven en el TEXTO de las
#      fichas de lead, así que --buscar es la vía correcta para eso.
#
# LEE, NUNCA ESCRIBE. Para sincronizar: group_sync.sh
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

usage() {
  cat <<'EOF'
Uso: group_history.sh <db> [filtros] [--limit N] [--json]

Filtros
  --buscar TEXTO   busca en el texto SIN acentos y sin distinguir mayúsculas
                   (usa texto_norm — la única forma correcta de buscar acá)
  --autor NOMBRE   fragmento del autor (también sin acentos)
  --desde AAAA-MM-DD / --hasta AAAA-MM-DD
  --dia AAAA-MM-DD atajo de --desde=--hasta
  --tipo T         messageType (conversation, imageMessage, audioMessage…)
  --solo-texto     descarta stickers/reacciones/adjuntos sin texto
  --hora-min N / --hora-max N   franja horaria (0-23, hora Bogotá)
  --contexto N     además de cada coincidencia, N mensajes antes y después
  --limit N        default 50; 0 = sin tope
  --json           salida machine-readable

Ejemplos
  group_history.sh only_closers --buscar "marulanda vasquez"
  group_history.sh only_closers --autor mateo --desde 2026-07-01 --hasta 2026-07-11
  group_history.sh only_closers --buscar "no se grabo" --contexto 3
EOF
}

DB=""; BUSCAR=""; AUTOR=""; DESDE=""; HASTA=""; TIPO=""
SOLO_TEXTO=0; HMIN=""; HMAX=""; CTX=0; LIMIT=50
while [[ $# -gt 0 ]]; do
  case "$1" in
    --buscar)     BUSCAR="${2:?}"; shift 2 ;;
    --autor)      AUTOR="${2:?}"; shift 2 ;;
    --desde)      DESDE="${2:?}"; shift 2 ;;
    --hasta)      HASTA="${2:?}"; shift 2 ;;
    --dia)        DESDE="${2:?}"; HASTA="$2"; shift 2 ;;
    --tipo)       TIPO="${2:?}"; shift 2 ;;
    --solo-texto) SOLO_TEXTO=1; shift ;;
    --hora-min)   HMIN="${2:?}"; shift 2 ;;
    --hora-max)   HMAX="${2:?}"; shift 2 ;;
    --contexto)   CTX="${2:?}"; shift 2 ;;
    --limit)      LIMIT="${2:?}"; shift 2 ;;
    --json)       FORMAT=json; shift ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "Argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
    *)            DB="$1"; shift ;;
  esac
done
[[ -z "$DB" ]] && { usage >&2; exit 2; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--limit debe ser un entero" >&2; exit 2; }
[[ "$CTX"   =~ ^[0-9]+$ ]] || { echo "--contexto debe ser un entero" >&2; exit 2; }
DBPATH="$(require_db "$DB")"

# --- frescura: sin esto, un cero es ambiguo ----------------------------------
FRESCO="$(sqlite_ro "$DBPATH" \
  "SELECT corrida_at FROM corridas ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)"
if [[ -n "$FRESCO" ]]; then
  EDAD_H="$(python3 -c '
import sys, datetime
try:
    t = datetime.datetime.fromisoformat(sys.argv[1])
except Exception:
    print(-1); raise SystemExit
print(int((datetime.datetime.now() - t).total_seconds() // 3600))' "$FRESCO")"
  if [[ "$EDAD_H" -ge 24 ]]; then
    echo "⚠️  último sync: $FRESCO (hace $((EDAD_H/24))d ${EDAD_H}h) — un resultado vacío puede ser desactualización. Corré: bash/whatsapp_evo_api/group_sync.sh" >&2
  else
    echo "(último sync: $FRESCO — hace ${EDAD_H}h)" >&2
  fi
else
  echo "⚠️  esta base no tiene bitácora de sync (\`corridas\`): no se puede saber qué tan fresca está." >&2
fi

# --- WHERE -------------------------------------------------------------------
# La aguja de --buscar se normaliza IGUAL que texto_norm (minúsculas, sin
# acentos) para que «Vásquez» y «vasquez» encuentren lo mismo.
sq() { printf "'%s'" "${1//\'/\'\'}"; }
W="1=1"
if [[ -n "$BUSCAR" ]]; then
  N="$(python3 -c '
import sys, unicodedata
s = unicodedata.normalize("NFD", sys.argv[1].lower())
print("".join(c for c in s if unicodedata.category(c) != "Mn"))' "$BUSCAR")"
  W="$W AND texto_norm LIKE $(sq "%$N%")"
fi
if [[ -n "$AUTOR" ]]; then
  N="$(python3 -c '
import sys, unicodedata
s = unicodedata.normalize("NFD", sys.argv[1].lower())
print("".join(c for c in s if unicodedata.category(c) != "Mn"))' "$AUTOR")"
  W="$W AND autor_norm LIKE $(sq "%$N%")"
fi
[[ -n "$DESDE" ]] && W="$W AND fecha >= $(sq "$DESDE")"
[[ -n "$HASTA" ]] && W="$W AND fecha <= $(sq "$HASTA")"
[[ -n "$TIPO"  ]] && W="$W AND tipo = $(sq "$TIPO")"
[[ -n "$HMIN"  ]] && W="$W AND hora >= $((HMIN))"
[[ -n "$HMAX"  ]] && W="$W AND hora <= $((HMAX))"
(( SOLO_TEXTO )) && W="$W AND texto IS NOT NULL AND trim(texto) <> ''"

LIM=""; (( LIMIT > 0 )) && LIM="LIMIT $LIMIT"

# --contexto: se resuelve por ts, trayendo los N vecinos de cada coincidencia.
if (( CTX > 0 )); then
  # Se numeran los mensajes por orden cronológico y se traen los que caen a ±N
  # posiciones de una coincidencia. La marca `>` distingue el hit de su contexto.
  SQL="WITH ord AS (SELECT *, row_number() OVER (ORDER BY ts) rn FROM mensajes),
            hit AS (SELECT rn FROM ord WHERE $W ORDER BY rn $LIM)
       SELECT CASE WHEN o.rn IN (SELECT rn FROM hit) THEN '>' ELSE ' ' END AS m,
              o.fecha, o.hora, o.autor, o.tipo, o.texto
       FROM ord o
       WHERE EXISTS (SELECT 1 FROM hit h WHERE o.rn BETWEEN h.rn - $CTX AND h.rn + $CTX)
       ORDER BY o.rn;"
else
  SQL="SELECT fecha, hora, autor, tipo, texto FROM mensajes WHERE $W ORDER BY ts $LIM;"
fi

if [[ "$FORMAT" == json ]]; then
  sqlite_ro "$DBPATH" -json "$SQL"
  echo
else
  N="$(sqlite_ro "$DBPATH" "SELECT count(*) FROM mensajes WHERE $W;")"
  echo "coincidencias: $N$( (( LIMIT > 0 && N > LIMIT )) && echo " (mostrando $LIMIT — subí con --limit 0)")" >&2
  sqlite_ro "$DBPATH" -header -column "$SQL"
fi
