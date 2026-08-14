#!/usr/bin/env bash
# bant_diff.sh — contrasta el BANT REGENERADO (db local sqlite `reportes_llamada`,
# escrita por el skill replicar-reporte-llamada) contra el BANT GUARDADO en
# Postgres (`call_reports_gemini` — el reporte de gemini congelado el 2026-08-13,
# antes de que el pipeline del Cerebro empezara a reemplazarlo en meeting_reports),
# llamada por llamada.
#
# Existe para separar dos causas que a simple vista se ven iguales. El 60% de
# los puntajes BANT no nulos de producción cae en 90-100, y el prompt de
# producción no trae ninguna rúbrica de anclaje. Eso puede ser del PROMPT o del
# MODELO, y la única forma de saberlo es cruzar los dos ejes:
#
#                     | prompt produccion | prompt mejorado
#   gemini-2.5-flash  | lo que hay en PG  | (falta: exige tocar producción)
#   claude            | ¿techo del prompt?| ¿lo arregla la rúbrica?
#
# Por eso cada fila local carga `generado_por` y `prompt_variante`, y por eso
# esta comparación NUNCA agrega sobre los dos ejes juntos.
#
# Uso: bant_diff.sh [--meeting ID|prefijo] [--resumen] [--json]
#   --resumen   agregado por (variante, modelo) en vez de fila por llamada
#
# ⚠️ Una corrida es una anécdota. El patrón del techo se midió sobre 940
# puntajes; el n de aquí sale impreso en cada salida precisamente para que
# nadie lea dos filas y concluya que algo quedó arreglado.
#
# Read-only de los dos lados: sqlite_ro (mode=ro, el motor rechaza escrituras)
# y psql_ro (default_transaction_read_only=on).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"
source "$here/../lib/sqlite.sh"

DB="reportes_llamada"
meeting="" resumen="" as_json=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --meeting) meeting="$2"; shift 2 ;;
    --resumen) resumen=1; shift ;;
    --json)    as_json=1; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

dbp="$(require_db "$DB")" || exit 1

filtro=""
if [[ -n "$meeting" ]]; then
  [[ "$meeting" =~ ^[0-9a-fA-F-]+$ ]] || { echo "Id inválido: '$meeting'" >&2; exit 2; }
  filtro="WHERE meeting_id LIKE '${meeting}%'"
fi

# ── lado local: lo que el skill generó ───────────────────────────────────────
local_json="$(sqlite_ro "$dbp" "
  SELECT coalesce(json_group_array(json_object(
    'meeting_id', meeting_id, 'corrida', corrida, 'modelo', generado_por,
    'variante', prompt_variante, 'budget', budget, 'authority', authority,
    'need', need, 'timeline', timeline, 'arquetipo', arquetipo,
    'prob', prob_cierre, 'status', call_status)), '[]') FROM bant $filtro;")"

if [[ "$local_json" == "[]" ]]; then
  echo "No hay reportes regenerados en la db local '$DB'${meeting:+ para $meeting}." >&2
  echo "Córrelos primero con el skill: /replicar-reporte-llamada <meeting-id>" >&2
  exit 1
fi

ids="$(printf '%s' "$local_json" | python3 -c "
import json,sys
print(','.join(\"'\"+r['meeting_id']+\"'\" for r in json.load(sys.stdin)))")"

# ── lado producción: lo que ya estaba guardado ───────────────────────────────
pg_json="$(psql_ro -t -A -c "
  SELECT coalesce(json_agg(json_build_object(
    'meeting_id', m.id::text,
    'lead', coalesce(r.report->'generalInformation'->>'leadName', split_part(m.name,' - ',1)),
    'fecha', to_char(m.scheduled_start_time,'YYYY-MM-DD'),
    'budget',    nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'budget'->>'score',''),'[^0-9]','','g'),'')::numeric,
    'authority', nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'authority'->>'score',''),'[^0-9]','','g'),'')::numeric,
    'need',      nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'need'->>'score',''),'[^0-9]','','g'),'')::numeric,
    'timeline',  nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'timeline'->>'score',''),'[^0-9]','','g'),'')::numeric,
    'arquetipo', r.report->'leadProfile'->'intelligentSegmentation'->'archetype'->>'name',
    'prob',      nullif(regexp_replace(coalesce(r.report->'leadProfile'->'predictionsAndRecommendations'->'closingProbability'->>'percentage',''),'[^0-9]','','g'),'')::numeric,
    'status',    r.report->'generalInformation'->>'callStatus')), '[]')
  FROM meetings m LEFT JOIN call_reports_gemini r ON r.meeting_id = m.id
  WHERE m.id::text IN ($ids);")"

RESUMEN="$resumen" ASJSON="$as_json" python3 - "$local_json" "$pg_json" <<'PY'
import json, os, sys

loc = json.loads(sys.argv[1])
pg  = {r['meeting_id']: r for r in json.loads(sys.argv[2])}
ITEMS = ('budget', 'authority', 'need', 'timeline')

def num(v):
    return None if v is None else float(v)

filas = []
for L in loc:
    P = pg.get(L['meeting_id'], {})
    f = {'id': L['meeting_id'][:8], 'lead': (P.get('lead') or '?')[:22], 'fecha': P.get('fecha'),
         'corrida': L['corrida'], 'variante': L['variante'], 'modelo': L['modelo'],
         'arq_gen': L.get('arquetipo'), 'arq_pg': P.get('arquetipo')}
    for k in ITEMS:
        g, p = num(L.get(k)), num(P.get(k))
        f[k] = {'gen': g, 'pg': p, 'delta': (None if g is None or p is None else g - p)}
    gs = [f[k]['gen'] for k in ITEMS]
    ps = [f[k]['pg'] for k in ITEMS]
    f['prom_gen'] = sum(gs) / 4 if all(v is not None for v in gs) else None
    f['prom_pg']  = sum(ps) / 4 if all(v is not None for v in ps) else None
    # Sin reporte en Postgres no hay contra qué comparar: no es un delta de 0.
    f['sin_pg'] = not P or all(v is None for v in ps)
    filas.append(f)

if os.environ.get('ASJSON'):
    print(json.dumps({'n': len(filas), 'filas': filas}, ensure_ascii=False, indent=2))
    sys.exit()

def fmt(v, w=5):
    return ('—' if v is None else (f'{v:g}' if isinstance(v, float) and v == int(v) else f'{v:.1f}')).rjust(w)

if os.environ.get('RESUMEN'):
    grupos = {}
    for f in filas:
        if f['sin_pg']:
            continue
        grupos.setdefault((f['variante'], f['modelo']), []).append(f)
    print(f"{'variante':<12} {'modelo':<16} {'n':>3} {'prom gen':>9} {'prom PG':>8} {'delta':>7} {'≥90 gen':>8} {'≥90 PG':>7}")
    print('-' * 78)
    for (var, mod), g in sorted(grupos.items()):
        pun_g = [f[k]['gen'] for f in g for k in ITEMS if f[k]['gen'] is not None]
        pun_p = [f[k]['pg']  for f in g for k in ITEMS if f[k]['pg']  is not None]
        a90g = 100 * sum(1 for v in pun_g if v >= 90) / len(pun_g) if pun_g else 0
        a90p = 100 * sum(1 for v in pun_p if v >= 90) / len(pun_p) if pun_p else 0
        pg_, pp_ = sum(pun_g) / len(pun_g), sum(pun_p) / len(pun_p)
        print(f"{var:<12} {mod:<16} {len(g):>3} {pg_:>9.1f} {pp_:>8.1f} {pg_-pp_:>+7.1f} {a90g:>7.0f}% {a90p:>6.0f}%")
    sin = sum(1 for f in filas if f['sin_pg'])
    print(f"\n{len(filas)-sin} llamada(s) comparada(s)" + (f"; {sin} sin reporte en Postgres (excluida(s))" if sin else ''))
    print("n bajo = anécdota. El techo de producción se midió sobre 940 puntajes.")
    sys.exit()

for f in filas:
    cab = f"{f['id']}  {f['lead']:<22} {f['fecha'] or '?'}   [{f['variante']} · {f['modelo']}]"
    print(cab)
    if f['sin_pg']:
        print("   (sin reporte en Postgres: no hay contra qué comparar)\n")
        continue
    print(f"   {'ítem':<10} {'gen':>5} {'PG':>5} {'Δ':>6}")
    for k in ITEMS:
        d = f[k]['delta']
        print(f"   {k:<10} {fmt(f[k]['gen'])} {fmt(f[k]['pg'])} "
              f"{('—' if d is None else f'{d:+g}'):>6}")
    dp = (None if f['prom_gen'] is None or f['prom_pg'] is None else f['prom_gen'] - f['prom_pg'])
    print(f"   {'PROMEDIO':<10} {fmt(f['prom_gen'])} {fmt(f['prom_pg'])} "
          f"{('—' if dp is None else f'{dp:+.1f}'):>6}")
    print(f"   arquetipo  gen: {f['arq_gen']!r}\n              PG : {f['arq_pg']!r}\n")

sin = sum(1 for f in filas if f['sin_pg'])
print(f"{len(filas)-sin} llamada(s) comparada(s)" + (f"; {sin} sin reporte en Postgres" if sin else ''))
PY
