#!/usr/bin/env bash
# comparativo_bant.sh — la matriz del experimento, una fila por LLAMADA y cuatro
# celdas por fila:
#
#                     | produccion    | mejorado   | mejorado-2
#   gemini-2.5-flash  |  celda 1 (PG) |  (no existe: exige tocar produccion)
#   claude            |  celda 2      |  celda 3   |  celda 4
#
# Las cuatro celdas se emiten SIEMPRE, existan o no. Una celda ausente no se
# omite: sale con `existe:0`, que es lo que le permite a la UI ofrecer el
# handle para mandarla a correr. Un hueco que no se ve no se llena.
#
# De dónde sale cada celda:
#   produccion-gemini  → db local, importada de Postgres por importar_produccion.sh
#   produccion-claude  → db local, corrida del skill con prompt-produccion.md
#   mejorado-claude    → db local, corrida del skill con prompt-mejorado.md
#   mejorado2-claude   → db local, corrida del skill con prompt-mejorado-2.md
#
# Por qué existe la cuarta celda: medido en pareado (mismo modelo, misma
# llamada), la rúbrica de `mejorado` bajó budget −16.7, timeline −15.0 y
# authority −13.3, pero `need` solo −1.7 — sigue clavado en 90. La causa es que
# sus anclas piden «que el lead lo haya dicho explícitamente», y agendar una
# llamada de ventas YA es decirlo. `mejorado-2` le da a `need` un eje propio
# (costo de la inacción) y no toca nada más.
#
# El universo de filas es la UNIÓN de la muestra trazada a ciegas (tabla
# `muestra`) y de toda llamada que ya tenga alguna corrida propia — así las
# llamadas piloto, anteriores a la muestra, no desaparecen del cuadro.
#
# Uso: comparativo_bant.sh [--pendientes] [--muestra] [--json]
#   --pendientes  solo llamadas a las que les falta alguna celda de claude
#   --muestra     solo las llamadas de la tabla `muestra`
#
# ⚠️ Este script MUESTRA los puntajes de gemini junto a los tuyos. Si estás a
# mitad de una muestra, no lo corras: ver la columna de control ancla la
# calibración de lo que te falta puntuar. Es la cuarta fuente de contaminación
# que lista el skill, y la más cómoda de abrir por accidente.
#
# Read-only de los dos lados: sqlite_ro (mode=ro) y psql_ro
# (default_transaction_read_only=on). Feeds the viz `bant_comparativo` source.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"
source "$here/../lib/sqlite.sh"

DB="reportes_llamada"
pendientes="" solo_muestra="" as_json=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pendientes) pendientes=1; shift ;;
    --muestra)    solo_muestra=1; shift ;;
    --json)       as_json=1; shift ;;
    -h|--help)    sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

dbp="$(require_db "$DB")" || exit 1

# ── lado local: la muestra + todas las corridas guardadas ────────────────────
universo="SELECT meeting_id FROM muestra"
[[ -z "$solo_muestra" ]] && universo="$universo UNION SELECT meeting_id FROM reportes"

local_json="$(sqlite_ro "$dbp" "
  WITH u AS ($universo)
  SELECT json_object(
    'llamadas', (SELECT coalesce(json_group_array(json_object(
        'meeting_id', u.meeting_id,
        'orden',  (SELECT m.orden        FROM muestra m WHERE m.meeting_id=u.meeting_id),
        'bloque', (SELECT m.bloque       FROM muestra m WHERE m.meeting_id=u.meeting_id),
        'chars',  (SELECT m.chars_reales FROM muestra m WHERE m.meeting_id=u.meeting_id),
        'buffer', (SELECT m.buffer       FROM muestra m WHERE m.meeting_id=u.meeting_id),
        'en_muestra', (SELECT count(*)   FROM muestra m WHERE m.meeting_id=u.meeting_id)
      )), '[]') FROM u),
    'corridas', (SELECT coalesce(json_group_array(json_object(
        'meeting_id', b.meeting_id, 'corrida', b.corrida, 'modelo', b.generado_por,
        'variante', b.prompt_variante, 'budget', b.budget, 'authority', b.authority,
        'need', b.need, 'timeline', b.timeline, 'prom', b.bant_prom,
        'arquetipo', b.arquetipo, 'prob', b.prob_cierre, 'status', b.call_status,
        'generado_at', (SELECT r.generado_at FROM reportes r
                        WHERE r.meeting_id=b.meeting_id AND r.corrida=b.corrida)
      )), '[]') FROM bant b)
  );")"

ids="$(printf '%s' "$local_json" | python3 -c "
import json,sys
ll = json.load(sys.stdin)['llamadas']
print(','.join(\"'\"+r['meeting_id']+\"'\" for r in ll) or \"''\")")"

# ── metadatos de la llamada (NO puntajes): lead, programa, fecha, closer ─────
# El closer sale del rastro CRM, la misma cadena documentada en calls.sh.
pg_json="$(psql_ro -t -A -c "
SELECT coalesce(json_agg(json_build_object(
  'meeting_id', m.id::text,
  'fecha', to_char(m.scheduled_start_time,'YYYY-MM-DD'),
  'lead',    coalesce(r.report->'generalInformation'->>'leadName', split_part(m.name,' - ',1)),
  'programa',coalesce(r.report->'generalInformation'->>'program',  split_part(m.name,' - ',2)),
  'proyecto', coalesce(pr.name,'—'),
  'closer',   coalesce(cl.closer,'—'),
  'tiene_reporte_pg', (r.report IS NOT NULL))), '[]')
FROM meetings m
LEFT JOIN projects pr ON pr.id=m.project_id
LEFT JOIN call_reports_gemini r ON r.meeting_id=m.id
LEFT JOIN LATERAL (
  SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS closer
  FROM crm_contacts c
  JOIN crm_opportunities o ON o.contact_id=c.id
  JOIN users u ON u.id=o.user_id
  JOIN persons p ON p.person_id=u.person_id
  WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
  ORDER BY (o.project_id = m.project_id) DESC, o.created_date DESC NULLS LAST
  LIMIT 1
) cl ON true
WHERE m.id::text IN ($ids);")"

PENDIENTES="$pendientes" ASJSON="$as_json" python3 - "$local_json" "$pg_json" <<'PY'
import json, os, sys

loc = json.loads(sys.argv[1])
pg  = {r['meeting_id']: r for r in json.loads(sys.argv[2])}
ITEMS = ('budget', 'authority', 'need', 'timeline')

# Las tres celdas, en orden fijo y con su regla de pertenencia. El orden es el
# del cuadro: control primero, luego los dos ejes de claude.
CELDAS = [
    ('produccion-gemini', 'producción · gemini',
     lambda c: c['variante'] == 'produccion' and (c['modelo'] or '').startswith('gemini')),
    ('produccion-claude', 'producción · claude',
     lambda c: c['variante'] == 'produccion' and not (c['modelo'] or '').startswith('gemini')),
    ('mejorado-claude', 'mejorado · claude',
     lambda c: c['variante'] == 'mejorado'),
    ('mejorado2-claude', 'mejorado-2 · claude',
     lambda c: c['variante'] == 'mejorado2'),
]
CLAUDE = ('produccion-claude', 'mejorado-claude', 'mejorado2-claude')

porllamada = {}
for c in loc['corridas']:
    porllamada.setdefault(c['meeting_id'], []).append(c)

def num(v):
    return None if v is None else float(v)

filas = []
for L in loc['llamadas']:
    mid = L['meeting_id']
    P = pg.get(mid, {})
    corridas = porllamada.get(mid, [])
    celdas = []
    for key, label, pred in CELDAS:
        # Varias corridas de la misma celda: gana la última guardada. Las
        # anteriores no se borran (la db es el registro), pero el cuadro
        # compara UNA por celda o deja de ser un cuadro.
        cs = sorted([c for c in corridas if pred(c)], key=lambda c: c.get('generado_at') or '')
        if not cs:
            # La celda de gemini no se corre: o ya está en Postgres y falta
            # importarla, o no existe. Y si falta importarla es casi siempre
            # A PROPÓSITO — el candado de importar_produccion.sh no la trae
            # hasta que esa llamada tenga una corrida propia, justo para no
            # dejarla a la vista de quien todavía tiene que puntuarla.
            if key == 'produccion-gemini':
                motivo = ('en Postgres, sin importar (candado: primero corre la tuya)'
                          if P.get('tiene_reporte_pg') else 'la llamada no tiene reporte en Postgres')
                handle = None
            else:
                motivo, handle = None, f"/replicar-reporte-llamada {mid[:8]} {key.split('-')[0]}"
            celdas.append({'celda': key, 'label': label, 'existe': 0,
                           'handle': handle, 'motivo': motivo})
            continue
        c = cs[-1]
        d = {'celda': key, 'label': label, 'existe': 1, 'corrida': c['corrida'],
             'modelo': c['modelo'], 'variante': c['variante'], 'generado_at': c.get('generado_at'),
             'arquetipo': c.get('arquetipo'), 'prob': num(c.get('prob')),
             'status': c.get('status'), 'n_corridas': len(cs)}
        for k in ITEMS:
            d[k] = num(c.get(k))
        vs = [d[k] for k in ITEMS]
        d['prom'] = sum(vs) / 4 if all(v is not None for v in vs) else None
        celdas.append(d)

    # El delta que importa: mejorado−producción, mismo modelo (claude) primero,
    # y contra gemini como respaldo. Nunca los dos mezclados en un solo número.
    ix = {c['celda']: c for c in celdas}
    mej, mj2 = ix['mejorado-claude'], ix['mejorado2-claude']
    pcl, pge = ix['produccion-claude'], ix['produccion-gemini']
    def delta(a, b):
        if not (a.get('existe') and b.get('existe')): return None
        if a.get('prom') is None or b.get('prom') is None: return None
        return round(a['prom'] - b['prom'], 2)

    filas.append({
        'meeting_id': mid, 'id8': mid[:8],
        'fecha': P.get('fecha'), 'lead': P.get('lead') or '?',
        'programa': P.get('programa'), 'proyecto': P.get('proyecto'), 'closer': P.get('closer'),
        'orden': L.get('orden'), 'bloque': L.get('bloque'),
        'chars': L.get('chars'), 'buffer': L.get('buffer'), 'en_muestra': L.get('en_muestra'),
        'faltan': sum(1 for k in CLAUDE if not ix[k]['existe']),
        'delta_vs_claude': delta(mej, pcl),
        'delta_vs_gemini': delta(mej, pge),
        # El ciclo 2 se mide contra su propio antecesor: mejorado-2 − mejorado
        # aísla el eje de `need`, que es lo único que cambia entre los dos.
        'delta_v2_vs_v1': delta(mj2, mej),
        'delta_v2_vs_claude': delta(mj2, pcl),
        'celdas': celdas,
    })

if os.environ.get('PENDIENTES'):
    filas = [f for f in filas if f['faltan']]

# Orden del cuadro: la muestra por su `orden` trazado a ciegas; lo demás, por
# fecha. Reordenar la muestra por puntaje sería leerla al revés.
filas.sort(key=lambda f: (0 if f['en_muestra'] else 1, f['orden'] or 0, f['fecha'] or ''))

if os.environ.get('ASJSON'):
    print(json.dumps(filas, ensure_ascii=False, indent=2))
    sys.exit()

def n(v, w=5):
    return ('—' if v is None else f'{v:g}').rjust(w)

print(f"{len(filas)} llamada(s) · {len(CELDAS)} celdas cada una\n")
for f in filas:
    m = '' if f['en_muestra'] else '  (piloto, fuera de la muestra)'
    print(f"── {f['id8']}  {f['fecha']}  {f['lead']}{m}")
    for c in f['celdas']:
        if not c['existe']:
            falta = c.get('motivo') or (c.get('handle') or 'no aplica')
            print(f"     {c['label']:<22} FALTA   → {falta}")
            continue
        print(f"     {c['label']:<22} B{n(c['budget'])} A{n(c['authority'])} "
              f"N{n(c['need'])} T{n(c['timeline'])}  prom {n(c['prom'])}   {c.get('arquetipo') or '—'}")
    if f['delta_vs_claude'] is not None:
        print(f"     Δ mejorado−producción (claude): {f['delta_vs_claude']:+g}")
    if f['delta_v2_vs_v1'] is not None:
        print(f"     Δ mejorado2−mejorado  (el eje de need): {f['delta_v2_vs_v1']:+g}")
    print()
PY
