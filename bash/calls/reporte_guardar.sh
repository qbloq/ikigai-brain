#!/usr/bin/env bash
# reporte_guardar.sh [WRITE local] — agrega N tiradas de un reporte de llamada y
# las persiste en la db local `generador_reportes` en UNA transacción.
#
# Es la mitad determinista del skill generar-reporte-llamada: los agentes
# producen las tiradas (JSON crudos), este script produce EL reporte:
#   · puntaje BANT   = mediana por ítem entre tiradas (robusta a la tirada suelta,
#                      que es la forma real del ruido — cohorte 3)
#   · arquetipo      = voto de mayoría (empate → la etiqueta de la tirada narrativa)
#   · narrativa      = la tirada cuyos 4 puntajes quedan más cerca de las medianas
#                      (el texto no se puede mediar; se elige el más representativo)
#   · baja_confianza = ítems cuyo rango entre tiradas supera --umbral (default 10,
#                      calibrado con el ruido de claude; provisional para otros modelos)
# El JSON agregado conserva el canon de 6 secciones y añade un bloque
# `_generacion` con la trazabilidad completa. Las tiradas crudas se guardan
# SIEMPRE junto al agregado: el agregado es derivable, las tiradas no.
#
# Regenerar un meeting nunca sobreescribe: crea generacion+1.
# Valida ANTES de escribir (claves de raíz + scores numéricos, como guardar.py);
# una tirada rota aborta todo — no existe el reporte a medias.
#
# DESTINO [WRITE pg] — desde 2026-08-13 esto es PRODUCCIÓN (migración 005):
#   --destino ambos (default)  sqlite local + Postgres
#             pg               solo Postgres
#             local            solo sqlite (el modo del experimento)
#   En Postgres escribe DOS cosas en una transacción:
#     · ikigaigm.call_reports (+ call_report_tiradas) — la fuente de verdad del
#       Cerebro, versionada por generación y con la procedencia en columnas.
#     · ikigaigm.meeting_reports — el ESCAPARATE del que lee la plataforma: se
#       upsertea el agregado, REEMPLAZANDO el reporte de gemini. El de gemini ya
#       está congelado en call_reports_gemini (celda de control del experimento);
#       --sin-escaparate omite este paso.
#
# Uso:
#   reporte_guardar.sh --meeting <uuid> --modelo <m> [--variante mejorado2]
#                      --tirada f1.json --tirada f2.json [--tirada …]
#                      [--umbral 10] [--destino ambos|pg|local] [--sin-escaparate]
#                      [--db generador_reportes] [--dry-run] [--json]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

meeting="" modelo="" variante="mejorado2" umbral="10" db="generador_reportes"
dry="" as_json="" destino="ambos" escaparate=1
declare -a tiradas=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --meeting)  meeting="$2"; shift 2 ;;
    --modelo)   modelo="$2"; shift 2 ;;
    --variante) variante="$2"; shift 2 ;;
    --tirada)   tiradas+=("$2"); shift 2 ;;
    --umbral)   umbral="$2"; shift 2 ;;
    --destino)  destino="$2"; shift 2 ;;
    --sin-escaparate) escaparate=0; shift ;;
    --db)       db="$2"; shift 2 ;;
    --dry-run)  dry=1; shift ;;
    --json)     as_json=1; shift ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1 (ver -h)" >&2; exit 2 ;;
  esac
done
case "$destino" in
  ambos|pg|local) ;;
  *) echo "--destino debe ser ambos|pg|local (ver -h)" >&2; exit 2 ;;
esac
[[ -n "$meeting" && -n "$modelo" && ${#tiradas[@]} -ge 2 ]] || {
  echo "faltan --meeting/--modelo o hay menos de 2 --tirada (ver -h)" >&2; exit 2; }

payload="$(mktemp)"; trap 'rm -f "$payload"' EXIT

sql="$(PAYLOAD="$payload" python3 - "$meeting" "$modelo" "$variante" "$umbral" "${tiradas[@]}" <<'PY'
import json, os, pathlib, sys, statistics as st
from collections import Counter
from datetime import datetime

meeting, modelo, variante, umbral = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
rutas = sys.argv[5:]
RAIZ = {"reportTitle", "generalInformation", "generalMetrics", "performanceInsights",
        "objectionsAndInsights", "leadProfile", "aiAgentConclusion"}
BANT = ("budget", "authority", "need", "timeline")

def sql_str(s):
    return "'" + str(s).replace("'", "''") + "'"

reps = []
for i, ruta in enumerate(rutas, 1):
    crudo = pathlib.Path(ruta).read_text().strip()
    if crudo.startswith("```"):
        crudo = crudo.split("```", 2)[1]
        crudo = crudo[4:] if crudo.startswith("json") else crudo
        crudo = crudo.strip()
    try:
        rep = json.loads(crudo)
    except json.JSONDecodeError as e:
        sys.exit(f"ERROR tirada {i} ({ruta}): JSON no parsea ({e}). No se escribió nada.")
    faltan = RAIZ - set(rep)
    if faltan:
        sys.exit(f"ERROR tirada {i}: faltan claves de raíz {sorted(faltan)}. No se escribió nada.")
    bant = (rep.get("leadProfile") or {}).get("bantAnalysis") or {}
    sin = [k for k in BANT if not isinstance((bant.get(k) or {}).get("score"), (int, float))]
    if sin:
        sys.exit(f"ERROR tirada {i}: ítems BANT sin score numérico {sin}. No se escribió nada.")
    reps.append(rep)

def score(rep, k):
    return rep["leadProfile"]["bantAnalysis"][k]["score"]
def arq(rep):
    return (((rep["leadProfile"].get("intelligentSegmentation") or {})
             .get("archetype") or {}).get("name"))

med = {k: st.median(score(r, k) for r in reps) for k in BANT}
rango = {k: max(score(r, k) for r in reps) - min(score(r, k) for r in reps) for k in BANT}
baja = [k for k in BANT if rango[k] > umbral]

# La tirada narrativa: menor distancia L1 a las medianas; empate → la primera.
dist = [sum(abs(score(r, k) - med[k]) for k in BANT) for r in reps]
n_narr = dist.index(min(dist)) + 1

votos = Counter(a for a in (arq(r) for r in reps) if a)
if votos:
    tope = max(votos.values())
    lideres = [a for a, n in votos.items() if n == tope]
    arq_narr = arq(reps[n_narr - 1])
    mayoria = arq_narr if arq_narr in lideres else lideres[0]
else:
    mayoria = None

agregado = json.loads(json.dumps(reps[n_narr - 1]))  # copia profunda de la narrativa
for k in BANT:
    agregado["leadProfile"]["bantAnalysis"][k]["score"] = med[k]
if mayoria is not None:
    agregado["leadProfile"]["intelligentSegmentation"]["archetype"]["name"] = mayoria
ahora = datetime.now().isoformat(timespec="seconds")
agregado["_generacion"] = {
    "n_tiradas": len(reps), "prompt_variante": variante, "modelo": modelo,
    "medianas": med, "rangos": rango, "baja_confianza": baja,
    "umbral_confianza": umbral, "arquetipo_votos": dict(votos),
    "tirada_narrativa": n_narr, "generado_at": ahora,
}

m = sql_str(meeting)
stmts = ["INSERT INTO reportes (meeting_id, generacion, prompt_variante, modelo, n_tiradas, "
         "bant_budget, bant_authority, bant_need, bant_timeline, "
         "rango_budget, rango_authority, rango_need, rango_timeline, "
         "baja_confianza, umbral_confianza, arquetipo, arquetipo_votos, arquetipo_unanime, "
         "tirada_narrativa, report, generado_at) VALUES ("
         + ", ".join([m,
             f"(SELECT coalesce(max(generacion),0)+1 FROM reportes WHERE meeting_id={m})",
             sql_str(variante), sql_str(modelo), str(len(reps)),
             str(med['budget']), str(med['authority']), str(med['need']), str(med['timeline']),
             str(rango['budget']), str(rango['authority']), str(rango['need']), str(rango['timeline']),
             sql_str(json.dumps(baja)), str(umbral),
             sql_str(mayoria) if mayoria is not None else "NULL",
             sql_str(json.dumps(dict(votos), ensure_ascii=False)),
             "1" if len(votos) == 1 else "0", str(n_narr),
             sql_str(json.dumps(agregado, ensure_ascii=False, separators=(",", ":"))),
             sql_str(ahora)]) + ");"]
rid = (f"(SELECT id FROM reportes WHERE meeting_id={m} "
       f"AND generacion=(SELECT max(generacion) FROM reportes WHERE meeting_id={m}))")
for i, rep in enumerate(reps, 1):
    stmts.append("INSERT INTO tiradas (reporte_id, n, report) VALUES ("
                 + ", ".join([rid, str(i),
                     sql_str(json.dumps(rep, ensure_ascii=False, separators=(",", ":")))]) + ");")
print("\n".join(stmts))

# El agregado completo, para los destinos que no son sqlite (Postgres). Se
# escribe a un archivo aparte: stdout ya carga el SQL de sqlite.
if os.environ.get("PAYLOAD"):
    pathlib.Path(os.environ["PAYLOAD"]).write_text(json.dumps({
        "meeting": meeting, "variante": variante, "modelo": modelo,
        "n_tiradas": len(reps), "medianas": med, "rangos": rango,
        "baja_confianza": baja, "umbral": umbral, "arquetipo": mayoria,
        "arquetipo_votos": dict(votos), "arquetipo_unanime": len(votos) == 1,
        "tirada_narrativa": n_narr, "generado_at": ahora,
        "agregado": agregado, "tiradas": reps,
    }, ensure_ascii=False))

# El resumen viaja por stderr para no mezclarse con el SQL de stdout.
det = {"medianas": med, "rangos": rango, "baja_confianza": baja,
       "arquetipo": mayoria, "arquetipo_votos": dict(votos),
       "tirada_narrativa": n_narr, "n_tiradas": len(reps)}
print("RESUMEN\t" + json.dumps(det, ensure_ascii=False), file=sys.stderr)
PY
)" || exit 1

if [[ "$destino" != "pg" ]]; then
  exec_args=("$repo/bash/localdb/db_exec.sh" "$db" "-")
  [[ -n "$dry" ]] && exec_args+=("--dry-run")
  printf '%s\n' "$sql" | "${exec_args[@]}" >&2
fi

# ── Postgres: la fuente de verdad (call_reports) + el escaparate ─────────────
if [[ "$destino" != "local" ]]; then
  pgsql="$(ESCAPARATE="$escaparate" python3 - "$payload" <<'PY'
import json, sys, os
from datetime import datetime

p = json.load(open(sys.argv[1]))
esc = os.environ.get("ESCAPARATE") == "1"

# ⚠️ `generado_at` se calcula con datetime.now() — hora LOCAL sin offset. La
# sqlite lo guarda como texto y da igual, pero Postgres lo interpretaría como
# UTC y el reporte nacería 5 horas en el pasado (el mismo espejismo de
# scheduled_start_time). Se le pega el offset local antes de escribirlo.
_ga = datetime.fromisoformat(p["generado_at"])
if _ga.tzinfo is None:
    _ga = _ga.astimezone()
p["generado_at_tz"] = _ga.isoformat()

def s(v):  # literal de texto
    return "'" + str(v).replace("'", "''") + "'"
def j(v):  # literal jsonb
    return s(json.dumps(v, ensure_ascii=False, separators=(",", ":"))) + "::jsonb"
def arr(xs):  # text[]
    return "ARRAY[" + ", ".join(s(x) for x in xs) + "]::text[]" if xs else "'{}'::text[]"

m, med, rng = s(p["meeting"]), p["medianas"], p["rangos"]
gen = f"(SELECT coalesce(max(generacion),0)+1 FROM ikigaigm.call_reports WHERE meeting_id={m})"
cols = ("meeting_id, generacion, prompt_variante, modelo, n_tiradas, "
        "bant_budget, bant_authority, bant_need, bant_timeline, "
        "rango_budget, rango_authority, rango_need, rango_timeline, "
        "baja_confianza, umbral_confianza, arquetipo, arquetipo_votos, "
        "arquetipo_unanime, tirada_narrativa, report, generado_at")
vals = ", ".join([
    m, gen, s(p["variante"]), s(p["modelo"]), str(p["n_tiradas"]),
    *(str(med[k]) for k in ("budget", "authority", "need", "timeline")),
    *(str(rng[k]) for k in ("budget", "authority", "need", "timeline")),
    arr(p["baja_confianza"]), str(p["umbral"]),
    s(p["arquetipo"]) if p["arquetipo"] is not None else "NULL",
    j(p["arquetipo_votos"]), "true" if p["arquetipo_unanime"] else "false",
    str(p["tirada_narrativa"]), j(p["agregado"]), s(p["generado_at_tz"]) + "::timestamptz",
])
tiradas = ", ".join(f"({i}, {j(r)})" for i, r in enumerate(p["tiradas"], 1))

# Una sola sentencia: si algo falla, no queda ni el agregado sin sus tiradas ni
# un escaparate apuntando a un reporte que no se guardó.
sql = f"""WITH nueva AS (
  INSERT INTO ikigaigm.call_reports ({cols}) VALUES ({vals}) RETURNING id
), tir AS (
  INSERT INTO ikigaigm.call_report_tiradas (call_report_id, n, report)
  SELECT nueva.id, v.n, v.rep FROM nueva, (VALUES {tiradas}) AS v(n, rep)
  RETURNING 1
)"""
if esc:
    sql += f"""
INSERT INTO ikigaigm.meeting_reports (meeting_id, report)
SELECT {m}, {j(p["agregado"])} FROM nueva
ON CONFLICT (meeting_id) DO UPDATE SET report = EXCLUDED.report, updated_at = now();"""
else:
    sql += "\nSELECT count(*) FROM tir;"
print(sql)
PY
)" || exit 1

  if [[ -n "$dry" ]]; then
    echo "DRY-RUN pg: no se escribió en Postgres. SQL que se habría corrido:" >&2
    printf '%s\n' "$pgsql" >&2
  else
    source "$repo/bash/lib/common.sh"
    printf '%s\n' "$pgsql" | psql_rw -v ON_ERROR_STOP=1 -q -f - >&2
    echo "pg: call_reports + tiradas$([[ "$escaparate" == 1 ]] && echo ' + meeting_reports (escaparate)')" >&2
  fi
fi

if [[ "$destino" == "pg" ]]; then
  python3 - "$payload" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
print(f'meeting {p["meeting"][:8]} · {p["variante"]} · {p["modelo"]} · {p["n_tiradas"]} tiradas')
for k in ("budget", "authority", "need", "timeline"):
    print(f'  {k:9s} mediana {p["medianas"][k]:>5} · rango {p["rangos"][k]:>4}')
print(f'  baja confianza: {", ".join(p["baja_confianza"]) or "—"}')
print(f'  arquetipo: {p["arquetipo"]!r} '
      f'{"(unánime)" if p["arquetipo_unanime"] else p["arquetipo_votos"]}')
print(f'  narrativa: tirada {p["tirada_narrativa"]} · {p["generado_at"]}')
PY
  exit 0
fi

# Estado persistido (o el que habría quedado, en dry-run): última generación.
source "$repo/bash/lib/sqlite.sh"
DB="$(require_db "$db")"
fila="$(sqlite_ro "$DB" "
  SELECT json_group_array(json_object(
    'id', id, 'meeting_id', meeting_id, 'generacion', generacion,
    'prompt_variante', prompt_variante, 'modelo', modelo, 'n_tiradas', n_tiradas,
    'bant_budget', bant_budget, 'bant_authority', bant_authority,
    'bant_need', bant_need, 'bant_timeline', bant_timeline,
    'rango_budget', rango_budget, 'rango_authority', rango_authority,
    'rango_need', rango_need, 'rango_timeline', rango_timeline,
    'baja_confianza', baja_confianza, 'arquetipo', arquetipo,
    'arquetipo_votos', arquetipo_votos, 'arquetipo_unanime', arquetipo_unanime,
    'tirada_narrativa', tirada_narrativa, 'generado_at', generado_at))
  FROM (SELECT * FROM reportes WHERE meeting_id = $(sql_str "$meeting")
        ORDER BY generacion DESC LIMIT 1);")"
if [[ -n "$as_json" ]]; then
  printf '%s\n' "${fila:-[]}"
else
  if [[ -n "$dry" ]]; then
    echo "DRY-RUN: nada persistido. Última generación existente para $meeting:"
  fi
  python3 - "${fila:-[]}" <<'PY'
import json, sys
rows = json.loads(sys.argv[1])
if not rows:
    print("(sin reportes previos para este meeting)"); raise SystemExit
r = rows[0]
print(f'reporte #{r["id"]} · meeting {r["meeting_id"][:8]} · generación {r["generacion"]}'
      f' · {r["prompt_variante"]} · {r["modelo"]} · {r["n_tiradas"]} tiradas')
for k in ("budget", "authority", "need", "timeline"):
    print(f'  {k:9s} mediana {r["bant_" + k]:>5} · rango {r["rango_" + k]:>4}')
baja = json.loads(r["baja_confianza"])
print(f'  baja confianza: {", ".join(baja) if baja else "—"}')
consenso = "(unánime)" if r["arquetipo_unanime"] else json.loads(r["arquetipo_votos"])
print(f'  arquetipo: {r["arquetipo"]!r} {consenso}')
print(f'  narrativa: tirada {r["tirada_narrativa"]} · {r["generado_at"]}')
PY
fi