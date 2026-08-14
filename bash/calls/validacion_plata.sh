#!/usr/bin/env bash
# validacion_plata.sh — ¿el puntaje PREDICE la plata?
#
# La pregunta que ni la cohorte 2 ni la 3 podían responder: consistencia no es
# verdad, y un prompt más duro no es un prompt más predictivo. Aquí el criterio
# externo es `installments` — plata que entró — y el contraste es cabeza a
# cabeza sobre LAS MISMAS llamadas:
#
#   v2-mediana  (db local `generador_reportes`: 3 tiradas, mediana por ítem)
#   producción  (Postgres `call_reports_gemini`: gemini, una tirada, sin rúbrica —
#                la celda de control, congelada antes del reemplazo de 2026-08-13)
#
# La métrica es **AUC** (= U de Mann-Whitney normalizada): la probabilidad de
# que, tomando un lead que pagó y uno que no, el puntaje ordene bien ese par.
# 0.5 = moneda al aire; 1.0 = separación perfecta. Se usa AUC y no "promedio de
# los que pagaron vs promedio de los que no" porque lo que se le pide al
# puntaje es ORDENAR una cola de leads, no acertar un valor.
#
# El p-valor es exacto (permutación completa sobre las C(n,k) asignaciones de
# etiqueta), no una aproximación normal: con n≈20 la normal miente.
#
# ⚠️ Diseño caso-control: la muestra se estratificó por desenlace (10/10), así
# que la tasa de conversión de la cohorte NO es la del negocio y las "bandas"
# de aquí no son probabilidades de cierre. El AUC sí es válido: no depende de
# la prevalencia. El desenlace se conoció DESPUÉS de puntuar, y los agentes que
# puntuaron solo vieron el transcript — la medición es ciega.
#
# Read-only sobre ambas fuentes. Uso: validacion_plata.sh [--json]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"
source "$here/../lib/sqlite.sh"

FORMAT="${FORMAT:-table}"
# --cohorte: 4 = la original · 5 = la RÉPLICA out-of-sample · todas = las 40.
# Se reportan las tres por separado a propósito: juntar 40 filas sin mirar la
# réplica sola escondería si el hallazgo no se sostuvo fuera de muestra.
cohorte="todas"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    --cohorte) cohorte="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1 (ver -h)" >&2; exit 2 ;;
  esac
done
[[ "$cohorte" =~ ^(4|5|todas)$ ]] || { echo "--cohorte debe ser 4, 5 o todas" >&2; exit 2; }
w_coh=""; [[ "$cohorte" != "todas" ]] && w_coh="WHERE m.cohorte = $cohorte"

DB="$(require_db generador_reportes)"

# Lado local: la cohorte + el reporte agregado (última generación por llamada).
local_json="$(sqlite_ro "$DB" "
SELECT json_group_array(json_object(
  'meeting_id', m.meeting_id, 'punto', m.punto, 'fecha', m.fecha,
  'estrato', m.estrato, 'pagado', m.pagado,
  'v2_budget', r.bant_budget, 'v2_authority', r.bant_authority,
  'v2_need', r.bant_need, 'v2_timeline', r.bant_timeline,
  'baja_confianza', r.baja_confianza, 'arquetipo', r.arquetipo,
  'arquetipo_unanime', r.arquetipo_unanime, 'n_tiradas', r.n_tiradas,
  'cohorte', m.cohorte))
FROM muestra_validacion m
JOIN reportes r ON r.meeting_id = m.meeting_id
 AND r.generacion = (SELECT max(generacion) FROM reportes r2 WHERE r2.meeting_id = m.meeting_id)
$w_coh;")"

# Lado producción: el BANT de gemini para esas mismas llamadas.
ids="$(printf '%s' "$local_json" | python3 -c "
import json,sys
print(','.join(\"'\"+r['meeting_id']+\"'\" for r in json.load(sys.stdin)))")"
prod_json="$(FORMAT=json emit "
SELECT mr.meeting_id::text AS meeting_id,
       (mr.report->'leadProfile'->'bantAnalysis'->'budget'->>'score')::float8 AS p_budget,
       (mr.report->'leadProfile'->'bantAnalysis'->'authority'->>'score')::float8 AS p_authority,
       (mr.report->'leadProfile'->'bantAnalysis'->'need'->>'score')::float8 AS p_need,
       (mr.report->'leadProfile'->'bantAnalysis'->'timeline'->>'score')::float8 AS p_timeline,
       mr.report->'leadProfile'->'intelligentSegmentation'->'archetype'->>'name' AS p_arquetipo,
       mr.report->'generalInformation'->>'leadName' AS lead
FROM call_reports_gemini mr WHERE mr.meeting_id::text IN ($ids)")"

FORMAT="$FORMAT" python3 - "$local_json" "$prod_json" <<'PY'
import json, os, random, sys
from itertools import combinations
from math import comb

loc = json.loads(sys.argv[1])
prod = {r["meeting_id"]: r for r in json.loads(sys.argv[2])}
ITEMS = ("budget", "authority", "need", "timeline")

filas = []
for r in loc:
    p = prod.get(r["meeting_id"], {})
    v2 = [r[f"v2_{k}"] for k in ITEMS]
    pr = [p.get(f"p_{k}") for k in ITEMS]
    filas.append({
        "id8": r["meeting_id"][:8], "punto": r["punto"], "fecha": r["fecha"],
        "lead": (p.get("lead") or "—")[:28],
        "pago": r["estrato"] == "convirtio", "pagado": r["pagado"], "cohorte": r["cohorte"],
        "v2": round(sum(v2) / 4, 1), "v2_items": dict(zip(ITEMS, v2)),
        "prod": round(sum(pr) / 4, 1) if all(x is not None for x in pr) else None,
        "prod_items": dict(zip(ITEMS, pr)),
        "baja_confianza": json.loads(r["baja_confianza"]),
        "arquetipo": r["arquetipo"], "arq_unanime": bool(r["arquetipo_unanime"]),
        "arq_prod": p.get("p_arquetipo"),
    })
filas.sort(key=lambda f: -(f["v2"]))

def auc_u(pos, neg):
    """AUC = P(puntaje de un pagador > el de un no pagador), empates = 0.5."""
    if not pos or not neg:
        return None, None
    u = sum((1.0 if a > b else 0.5 if a == b else 0.0) for a in pos for b in neg)
    return u / (len(pos) * len(neg)), u

def midranks(vals):
    """Rangos con empates promediados. Con estos, la suma de rangos de un
    grupo determina su AUC exactamente — incluidos los empates a 0.5."""
    orden = sorted(range(len(vals)), key=lambda i: vals[i])
    r = [0.0] * len(vals)
    i = 0
    while i < len(orden):
        j = i
        while j + 1 < len(orden) and vals[orden[j + 1]] == vals[orden[i]]:
            j += 1
        medio = (i + j) / 2 + 1                      # rangos base 1
        for k in range(i, j + 1):
            r[orden[k]] = medio
        i = j + 1
    return r

MC_N, MC_SEMILLA = 200_000, 20260809   # semilla fija: el p es reproducible

def p_exacto(vals, etiquetas):
    """p de dos colas por permutación de las etiquetas. Se enumera la suma de
    rangos y no el AUC recalculado: son la misma estadística
    (U = R1 − n1(n1+1)/2), pero es mucho más barato.

    Exacto mientras C(n,k) sea enumerable; por encima, Monte Carlo con semilla
    fija — con n=40 y k=20 las combinaciones son 1.4e11 y enumerarlas no es una
    opción. El método usado se devuelve junto al valor: un p de MC tiene su
    propio error (~±0.001 con 200k muestras) y quien lo lea debe saberlo."""
    n, k = len(vals), sum(etiquetas)
    if k == 0 or k == n:
        return None, None
    r = midranks(vals)
    obs = sum(ri for ri, e in zip(r, etiquetas) if e)
    centro = k * (n + 1) / 2          # suma de rangos esperada bajo H0
    desvio = abs(obs - centro)
    total_comb = comb(n, k)
    if total_comb <= 2_000_000:
        extremos = sum(1 for c in combinations(range(n), k)
                       if abs(sum(r[i] for i in c) - centro) >= desvio - 1e-9)
        return extremos / total_comb, "exacto"
    rnd = random.Random(MC_SEMILLA)
    idx = list(range(n))
    extremos = 0
    for _ in range(MC_N):
        rnd.shuffle(idx)
        if abs(sum(r[i] for i in idx[:k]) - centro) >= desvio - 1e-9:
            extremos += 1
    # (extremos+1)/(N+1): el estimador sin sesgo de un p por remuestreo, que
    # además nunca devuelve 0 — «no vimos ninguno» no es «es imposible».
    return (extremos + 1) / (MC_N + 1), f"MC {MC_N//1000}k"

def analiza(clave, sub=None):
    vals, et = [], []
    for f in filas:
        v = f[clave] if sub is None else f[f"{clave}_items"][sub]
        if v is None:
            continue
        vals.append(v); et.append(1 if f["pago"] else 0)
    pos = [v for v, e in zip(vals, et) if e]
    neg = [v for v, e in zip(vals, et) if not e]
    a, _ = auc_u(pos, neg)
    pv, pm = p_exacto(vals, et)
    return {"n": len(vals), "n_pago": len(pos), "auc": round(a, 3) if a is not None else None,
            "media_pago": round(sum(pos) / len(pos), 1) if pos else None,
            "media_no": round(sum(neg) / len(neg), 1) if neg else None,
            "p_exacto": pv, "p_metodo": pm}

resumen = {"v2_promedio": analiza("v2"), "produccion_promedio": analiza("prod")}
por_item = []
for k in ITEMS:
    por_item.append({"item": k, "v2": analiza("v2", k), "produccion": analiza("prod", k)})

# ¿Cuántos empates produce cada puntaje? Un puntaje que empata no ordena.
def empates(clave):
    vs = [f[clave] for f in filas if f[clave] is not None]
    return len(vs) - len(set(vs))

out = {
    "filas": filas,
    "resumen": resumen,
    "por_item": por_item,
    "empates": {"v2": empates("v2"), "produccion": empates("prod")},
    "banderas": {
        "con_baja_confianza": sum(1 for f in filas if f["baja_confianza"]),
        "arquetipo_unanime": sum(1 for f in filas if f["arq_unanime"]),
    },
    "nota": ("AUC = P(el puntaje de un lead que pagó supere al de uno que no). "
             "0.5 = azar. Muestra caso-control 10/10: el AUC es válido (no depende "
             "de prevalencia), pero las tasas de conversión por banda NO lo son."),
}

if os.environ.get("FORMAT") == "json":
    print(json.dumps(out, ensure_ascii=False))
    raise SystemExit

R = resumen
print(f"\nAUC contra plata — cohorte {os.environ.get('COHORTE','todas')} — {R['v2_promedio']['n']} llamadas, {R['v2_promedio']['n_pago']} pagaron\n")
print(f"{'puntaje':<22}{'AUC':>7}{'p':>11}{'  método':<12}{'pagó':>8}{'no pagó':>10}{'empates':>9}")
for nom, key, emp in (("v2 (mediana de 3)", "v2_promedio", out["empates"]["v2"]),
                      ("producción (gemini)", "produccion_promedio", out["empates"]["produccion"])):
    d = R[key]
    if d["auc"] is None:
        print(f"{nom:<22}{'—':>7}"); continue
    p = f"{d['p_exacto']:.4f}" if d["p_exacto"] is not None else "—"
    met = f" ({d['p_metodo']})" if d.get("p_metodo") else ""
    print(f"{nom:<22}{d['auc']:>7.3f}{p:>11}{met:<12}{d['media_pago']:>8}{d['media_no']:>10}{emp:>9}")

print(f"\n{'por ítem':<12}{'AUC v2':>9}{'AUC prod':>10}   (media pagó / media no)")
for d in por_item:
    v, p = d["v2"], d["produccion"]
    pa = f"{p['auc']:.3f}" if p["auc"] is not None else "—"
    print(f"{d['item']:<12}{v['auc']:>9.3f}{pa:>10}   v2 {v['media_pago']}/{v['media_no']}"
          f"  ·  prod {p['media_pago']}/{p['media_no']}")

print(f"\n{'ranking por v2':<32}{'v2':>6}{'prod':>7}  coh  pagó")
for f in filas:
    marca = "✓ $" + f"{f['pagado']:,.0f}" if f["pago"] else "·"
    bc = f"  ⚠{','.join(f['baja_confianza'])}" if f["baja_confianza"] else ""
    print(f"{f['id8']} {f['lead']:<23}{f['v2']:>6}{f['prod'] if f['prod'] else '—':>7}   c{f['cohorte']}  {marca}{bc}")

b = out["banderas"]
print(f"\nbanderas: {b['con_baja_confianza']}/{len(filas)} con ítem de baja confianza · "
      f"{b['arquetipo_unanime']}/{len(filas)} arquetipo unánime 3/3")
print(f"\n{out['nota']}\n")
PY
