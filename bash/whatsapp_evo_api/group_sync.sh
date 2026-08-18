#!/usr/bin/env bash
# group_sync.sh — WRITE (local): baja el historial de UN grupo de WhatsApp desde
# la Evolution API a una base SQLite local.
#
# POR QUÉ EXISTE
# El grupo ONLY CLOSERS resultó ser una fuente de verdad operativa: las fichas de
# lead, los cierres anunciados y las fallas de la app viven ahí y en ningún otro
# lado. El cruce que recuperó las 6 ventas perdidas de Mateo (docs/only-closers-
# informe.md §8) se apoyó en ese historial. Bajarlo a mano era un artefacto de
# sesión; esto lo vuelve herramienta.
#
# LECTURA Y ESCRITURA SON OPERACIONES SEPARADAS
# Esto solo SINCRONIZA. Para consultar se usa el dominio localdb, que ya existe:
#   bash/localdb/db_query.sh <db> "SELECT … FROM mensajes WHERE …"
# No hay un lector propio a propósito: sería duplicar db_query.sh.
#
# QUÉ ESCRIBE — y qué deliberadamente no
#   · `mensajes` : INSERT OR IGNORE por el id de Evolution. Idempotente: volver
#                  a correrlo nunca duplica ni pisa. NUNCA BORRA — un mensaje
#                  eliminado en WhatsApp se queda en la copia; acá la copia ES
#                  el registro.
#   · `corridas` : una fila por ejecución (la bitácora de frescura). Sin esto,
#                  una búsqueda que da cero no distingue "no existe" de "la
#                  copia está vieja" — el error que casi cometimos con Renan.
#   · Postgres   : jamás. Esta capa solo toca la SQLite local.
#
# NO LE PEGA A LOS SERVIDORES DE META. `/chat/findMessages` consulta el store
# LOCAL de Evolution (Baileys guarda lo que llega por el websocket), no a
# WhatsApp. Verificado 2026-08-13: grupos sin tráfico desde el emparejamiento
# devuelven 0 mensajes aunque tengan años de historia. Paginar acá no cuenta
# como actividad ante Meta; lo que sí arriesga la cuenta son los ENVÍOS masivos.
#
# INCREMENTAL POR DEFECTO: pagina desde lo más reciente y para cuando una página
# entera ya está en la base. Ponerse al día son 2-3 páginas, no 324.
#
# CREDENCIALES: EVOLUTION_API_{URL,KEY,INSTANCE} de .env.
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
cd "$REPO_ROOT"
# shellcheck disable=SC1091
source .env

usage() {
  cat <<'EOF'
Uso: group_sync.sh <grupo> [--db NOMBRE] [--completo] [--paginas N] [--dry-run] [--json]

  <grupo>      JID (…@g.us) o fragmento del nombre del grupo
  --db N       base destino (default: derivada del nombre del grupo)
  --completo   barre TODO el historial en vez de parar en lo ya conocido
  --paginas N  tope de páginas por corrida (0 = sin tope, default)
  --dry-run    consulta y reporta, no escribe nada
  --json       salida machine-readable

WRITE local: escribe en data/sqlite/<db>.db (mensajes, corridas).
Para LEER: bash/localdb/db_query.sh <db> "SELECT … FROM mensajes"
EOF
}

GRUPO=""; DB=""; COMPLETO=0; MAXPAG=0; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)       DB="${2:?}"; shift 2 ;;
    --completo) COMPLETO=1; shift ;;
    --paginas)  MAXPAG="${2:?}"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "Argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
    *)          GRUPO="$1"; shift ;;
  esac
done
[[ -z "$GRUPO" ]] && { usage >&2; exit 2; }
[[ "$MAXPAG" =~ ^[0-9]+$ ]] || { echo "--paginas debe ser un entero" >&2; exit 2; }
: "${EVOLUTION_API_URL:?falta EVOLUTION_API_URL en .env}"
: "${EVOLUTION_API_KEY:?falta EVOLUTION_API_KEY en .env}"
: "${EVOLUTION_API_INSTANCE:?falta EVOLUTION_API_INSTANCE en .env}"

# --- resolver el grupo -------------------------------------------------------
# Se resuelve contra /chat/findChats (el store local) y no contra
# /group/fetchAllGroups: el mismo grupo puede aparecer con OTRO jid en el
# listado live, y ese jid no tiene mensajes. El que sirve es el del store.
if [[ "$GRUPO" == *"@g.us" ]]; then
  JID="$GRUPO"; NOMBRE="$GRUPO"
else
  read -r JID NOMBRE < <(curl -s --max-time 30 -X POST \
      -H "apikey: ${EVOLUTION_API_KEY}" -H "Content-Type: application/json" \
      "${EVOLUTION_API_URL}/chat/findChats/${EVOLUTION_API_INSTANCE}" -d '{}' \
    | python3 -c '
import sys, json
frag = sys.argv[1].lower()
d = json.load(sys.stdin)
chats = d if isinstance(d, list) else (d.get("chats") or {}).get("records") or d.get("records") or []
hits = [c for c in chats
        if str(c.get("remoteJid","")).endswith("@g.us")
        and frag in str(c.get("pushName") or c.get("name") or "").lower()]
if not hits:
    print("", ""); sys.exit(0)
if len(hits) > 1:
    print("Varios grupos coinciden con ese fragmento:", file=sys.stderr)
    for c in hits[:10]:
        print("  ", c.get("remoteJid"), "|", c.get("pushName") or c.get("name"), file=sys.stderr)
    print("", ""); sys.exit(0)
c = hits[0]
print(c.get("remoteJid"), (c.get("pushName") or c.get("name") or "").replace(" ", "_"))' "$GRUPO")
  [[ -z "${JID:-}" ]] && { echo "No se resolvió el grupo '$GRUPO' (usa el JID o afina el fragmento)" >&2; exit 1; }
fi

# base destino: la dada, o derivada del nombre del grupo
if [[ -z "$DB" ]]; then
  DB="$(printf '%s' "${NOMBRE:-$JID}" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '_' | sed 's/^_//; s/_$//')"
  [[ -z "$DB" ]] && DB="grupo_wa"
fi
DBPATH="$(db_path "$DB")"
mkdir -p "$LOCALDB_DIR"

# --- esquema + migración (idempotente, ANTES de insertar) --------------------
# Va acá y no en el SQL generado porque una base creada por una versión previa
# no tiene texto_norm/autor_norm, y un INSERT con más columnas que la tabla
# falla. ALTER … ADD COLUMN es no-op ruidoso si ya existe: se ignora el error.
if (( ! DRY )); then
  sqlite_rw "$DBPATH" <<'DDL'
CREATE TABLE IF NOT EXISTS mensajes (
  id TEXT PRIMARY KEY,          -- key.id de Evolution
  ts INTEGER NOT NULL,          -- epoch
  fecha TEXT NOT NULL,          -- YYYY-MM-DD (Bogotá)
  hora INTEGER NOT NULL,        -- 0-23 (Bogotá)
  dia_semana INTEGER NOT NULL,  -- 0=lunes … 6=domingo
  autor TEXT,                   -- pushName
  numero TEXT,                  -- LID del participante (NO es el teléfono)
  from_me INTEGER NOT NULL,
  tipo TEXT,
  texto TEXT,
  texto_norm TEXT,              -- minúsculas y SIN acentos — buscar SIEMPRE acá
  quoted_numero TEXT,
  quoted_texto TEXT,
  reaccion TEXT,
  reaccion_a TEXT,
  autor_norm TEXT               -- autor sin acentos, mismo motivo
);
CREATE INDEX IF NOT EXISTS ix_mensajes_fecha ON mensajes(fecha);
CREATE TABLE IF NOT EXISTS corridas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  corrida_at TEXT NOT NULL,
  jid TEXT NOT NULL,
  paginas INTEGER, leidos INTEGER, nuevos INTEGER,
  total_upstream INTEGER, completo INTEGER,
  fecha_min TEXT, fecha_max TEXT
);
DDL
  for col in texto_norm autor_norm; do
    sqlite_rw "$DBPATH" "ALTER TABLE mensajes ADD COLUMN $col TEXT;" 2>/dev/null || true
  done
  sqlite_rw "$DBPATH" "CREATE INDEX IF NOT EXISTS ix_mensajes_autor ON mensajes(autor_norm);"
fi

# --- ids ya conocidos (para el corte incremental) ----------------------------
KNOWN="$(mktemp)"; trap 'rm -f "$KNOWN"' EXIT
if [[ -f "$DBPATH" ]] && (( ! COMPLETO )); then
  sqlite_ro "$DBPATH" "SELECT id FROM mensajes;" 2>/dev/null >"$KNOWN" || : >"$KNOWN"
fi

# --- traer + normalizar + generar SQL ----------------------------------------
SQL="$(mktemp)"; trap 'rm -f "$KNOWN" "$SQL"' EXIT
export JID MAXPAG COMPLETO KNOWN
export EVOLUTION_API_URL EVOLUTION_API_KEY EVOLUTION_API_INSTANCE
STATS="$(python3 - "$SQL" <<'PY'
import json, os, sys, urllib.request, datetime, unicodedata, zoneinfo

out_sql = sys.argv[1]
URL  = os.environ["EVOLUTION_API_URL"].rstrip("/")
KEY  = os.environ["EVOLUTION_API_KEY"]
INST = os.environ["EVOLUTION_API_INSTANCE"]
JID  = os.environ["JID"]
MAXPAG = int(os.environ["MAXPAG"])
COMPLETO = os.environ["COMPLETO"] == "1"
BOG = zoneinfo.ZoneInfo("America/Bogota")

known = set()
with open(os.environ["KNOWN"]) as fh:
    for line in fh:
        line = line.strip()
        if line:
            known.add(line)

def fetch(page):
    body = json.dumps({"where": {"key": {"remoteJid": JID}}, "page": page}).encode()
    req = urllib.request.Request(
        f"{URL}/chat/findMessages/{INST}", data=body,
        headers={"apikey": KEY, "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.load(r)

recs, page, pages, total = [], 1, None, None
while True:
    d = fetch(page)
    meta = d.get("messages") or {}
    batch = meta.get("records") or []
    if pages is None:
        pages = meta.get("pages") or 0
        total = meta.get("total")
    nuevos_en_pagina = [m for m in batch
                        if ((m.get("key") or {}).get("id")) not in known]
    recs.extend(batch)
    if not batch or page >= pages:
        break
    # corte incremental: una página entera ya conocida = estamos al día
    if not COMPLETO and not nuevos_en_pagina:
        break
    if MAXPAG and page >= MAXPAG:
        break
    page += 1

def norm(s):
    if s is None:
        return None
    s = unicodedata.normalize("NFD", str(s).lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")

def esc(s):
    return "NULL" if s is None else "'" + str(s).replace("'", "''") + "'"

def text_of(m):
    msg = m.get("message") or {}
    return (msg.get("conversation")
            or (msg.get("extendedTextMessage") or {}).get("text")
            or (msg.get("imageMessage") or {}).get("caption")
            or (msg.get("videoMessage") or {}).get("caption")
            or (msg.get("documentMessage") or {}).get("caption"))

def quoted_of(m):
    msg = m.get("message") or {}
    for k in ("extendedTextMessage", "imageMessage", "videoMessage", "audioMessage"):
        ctx = (msg.get(k) or {}).get("contextInfo") or {}
        if ctx.get("stanzaId"):
            q = ctx.get("quotedMessage") or {}
            return ctx.get("participant"), (q.get("conversation")
                                            or (q.get("extendedTextMessage") or {}).get("text"))
    return None, None

def reaction_of(m):
    r = (m.get("message") or {}).get("reactionMessage") or {}
    return (r.get("text"), (r.get("key") or {}).get("id")) if r else (None, None)

seen, filas, nuevos = set(), [], 0
fmin = fmax = None
for m in recs:
    k = m.get("key") or {}
    mid = k.get("id")
    if not mid or mid in seen:
        continue
    seen.add(mid)
    if mid not in known:
        nuevos += 1
    ts = m.get("messageTimestamp") or 0
    dt = datetime.datetime.fromtimestamp(ts, BOG)
    f = dt.strftime("%Y-%m-%d")
    fmin = f if fmin is None or f < fmin else fmin
    fmax = f if fmax is None or f > fmax else fmax
    numero = (k.get("participant") or m.get("participant") or "").split("@")[0] or None
    qn, qt = quoted_of(m)
    remoji, rid = reaction_of(m)
    txt = text_of(m)
    filas.append(
        "INSERT OR IGNORE INTO mensajes VALUES (%s,%d,%s,%d,%d,%s,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s);" % (
            esc(mid), ts, esc(f), dt.hour, dt.weekday(),
            esc(m.get("pushName")), esc(numero), 1 if k.get("fromMe") else 0,
            esc(m.get("messageType")), esc(txt), esc(norm(txt)),
            esc((qn or "").split("@")[0] or None), esc(qt),
            esc(remoji), esc(rid), esc(norm(m.get("pushName")))))

with open(out_sql, "w") as fh:
    fh.write("\n".join(filas) + ("\n" if filas else ""))

json.dump({"paginas": page, "pages_upstream": pages, "total_upstream": total,
           "leidos": len(seen), "nuevos": nuevos,
           "fecha_min": fmin, "fecha_max": fmax}, sys.stdout)
PY
)"

PAGINAS=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["paginas"])' "$STATS")
PAGUP=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["pages_upstream"] or 0)' "$STATS")
LEIDOS=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["leidos"])' "$STATS")
NUEVOS=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["nuevos"])' "$STATS")
TOTUP=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["total_upstream"] or 0)' "$STATS")
FMIN=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["fecha_min"] or "")' "$STATS")
FMAX=$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["fecha_max"] or "")' "$STATS")

RENORM=0
if (( DRY )); then
  echo "DRY-RUN — no se escribió nada" >&2
else
  sqlite_rw "$DBPATH" <"$SQL"

  # --- backfill de las columnas normalizadas ---------------------------------
  # Filas viejas (o insertadas por una versión previa) no tienen texto_norm.
  # Se normaliza en Python porque SQLite no trae unaccent(). Idempotente: solo
  # toca las que están en NULL.
  PEND="$(sqlite_ro "$DBPATH" "SELECT count(*) FROM mensajes
            WHERE (texto IS NOT NULL AND texto_norm IS NULL)
               OR (autor IS NOT NULL AND autor_norm IS NULL);")"
  if [[ "${PEND:-0}" -gt 0 ]]; then
    BF="$(mktemp)"
    sqlite_ro "$DBPATH" -json "SELECT id, texto, autor FROM mensajes
        WHERE (texto IS NOT NULL AND texto_norm IS NULL)
           OR (autor IS NOT NULL AND autor_norm IS NULL);" \
    | python3 -c '
import json, sys, unicodedata
def norm(s):
    if s is None: return None
    s = unicodedata.normalize("NFD", str(s).lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")
def esc(s):
    return "NULL" if s is None else "'"'"'" + str(s).replace("'"'"'", "'"'"''"'"'") + "'"'"'"
for r in json.load(sys.stdin):
    print("UPDATE mensajes SET texto_norm=%s, autor_norm=%s WHERE id=%s;"
          % (esc(norm(r.get("texto"))), esc(norm(r.get("autor"))), esc(r["id"])))' >"$BF"
    sqlite_rw "$DBPATH" <"$BF"
    RENORM="$PEND"
    rm -f "$BF"
  fi

  sqlite_rw "$DBPATH" "INSERT INTO corridas
    (corrida_at, jid, paginas, leidos, nuevos, total_upstream, completo, fecha_min, fecha_max)
    VALUES (datetime('now','localtime'), '$JID', $PAGINAS, $LEIDOS, $NUEVOS, $TOTUP, $COMPLETO,
            $( [[ -n "$FMIN" ]] && echo "'$FMIN'" || echo NULL ),
            $( [[ -n "$FMAX" ]] && echo "'$FMAX'" || echo NULL ));"
fi

if [[ "$FORMAT" == json ]]; then
  python3 -c '
import json, sys
d = json.loads(sys.argv[1]); d["db"] = sys.argv[2]; d["jid"] = sys.argv[3]
d["dry_run"] = sys.argv[4] == "1"
json.dump(d, sys.stdout)' "$STATS" "$DB" "$JID" "$DRY"
  echo
else
  printf 'grupo    : %s\nbase     : %s\npáginas  : %s de %s (upstream: %s mensajes)\nleídos   : %s (%s nuevos)\nrango    : %s → %s\n' \
    "$JID" "$DBPATH" "$PAGINAS" "$PAGUP" "$TOTUP" "$LEIDOS" "$NUEVOS" "${FMIN:-—}" "${FMAX:-—}"
  (( RENORM > 0 )) && printf 'normaliz.: %s filas rellenadas (texto_norm/autor_norm)\n' "$RENORM"
  if (( ! DRY )); then
    sqlite_ro "$DBPATH" "SELECT 'en base  : '||count(*)||' mensajes ('||min(fecha)||' → '||max(fecha)||')' FROM mensajes;"
  fi
fi
