#!/usr/bin/env bash
# variabilidad_bant.sh — test-retest del reporte de llamada: ¿cuánto del puntaje
# es el lead y cuánto es el dado?
#
# Lee las tiradas repetidas de la cohorte 3 (tabla `muestra3` + corridas
# `<id8>-mejorado2-t<n>` en `reportes`, db local sqlite) y emite UN objeto:
#
#   llamadas[]  una por punto de la muestra: sus tiradas completas, y por ítem
#               {scores, media, sd, rango}; arquetipos con su moda.
#   por_item[]  la descomposición señal/ruido: sd_intra (pooled, el RUIDO del
#               proceso), sd_inter (la SEÑAL entre leads) e ICC(1,1) — la
#               fracción de la varianza que es del lead y no de la tirada.
#   global      n, lectura sugerida del ICC y el intervalo mínimo distinguible
#               (dos leads a menos de ~2.8·sd_intra no son distinguibles con
#               una sola corrida).
#
# Existe porque el reporte lo produce un LLM y una corrida sola es UNA muestra
# de una distribución: sin esta medición, comparar dos leads (o dos prompts)
# es indistinguible de comparar dos tiradas. Read-only (sqlite_ro).
#
# Uso: variabilidad_bant.sh [--json]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/sqlite.sh"

DB="$(require_db reportes_llamada)"
as_json=""
[[ "${1:-}" == "--json" ]] && as_json=1

datos=$(sqlite_ro "$DB" "
SELECT json_object(
  'muestra', (SELECT json_group_array(json_object(
      'meeting_id', meeting_id, 'fecha', fecha, 'lead', lead, 'punto', punto))
    FROM (SELECT * FROM muestra3 ORDER BY punto)),
  'corridas', (SELECT json_group_array(json_object(
      'meeting_id', r.meeting_id, 'corrida', r.corrida,
      'budget',   json_extract(r.report,'\$.leadProfile.bantAnalysis.budget.score'),
      'authority',json_extract(r.report,'\$.leadProfile.bantAnalysis.authority.score'),
      'need',     json_extract(r.report,'\$.leadProfile.bantAnalysis.need.score'),
      'timeline', json_extract(r.report,'\$.leadProfile.bantAnalysis.timeline.score'),
      'arquetipo',json_extract(r.report,'\$.leadProfile.intelligentSegmentation.archetype.name')))
    FROM reportes r
    JOIN muestra3 m ON m.meeting_id = r.meeting_id
    WHERE r.prompt_variante='mejorado2' AND r.corrida LIKE '%-t_')
);")

python3 - "$datos" <<'PY'
import json, sys, statistics as st
from collections import Counter

D = json.loads(sys.argv[1])
ITEMS = ("budget", "authority", "need", "timeline")
por_meeting = {}
for c in (D["corridas"] or []):
    por_meeting.setdefault(c["meeting_id"], []).append(c)

llamadas = []
for m in (D["muestra"] or []):
    cs = sorted(por_meeting.get(m["meeting_id"], []), key=lambda c: c["corrida"])
    tiradas = []
    for c in cs:
        vs = [c[k] for k in ITEMS]
        tiradas.append({"t": c["corrida"].rsplit("-t", 1)[-1],
                        **{k: c[k] for k in ITEMS},
                        "prom": round(sum(vs) / 4, 1) if all(v is not None for v in vs) else None,
                        "arquetipo": c["arquetipo"]})
    items = {}
    for k in ITEMS:
        sc = [c[k] for c in cs if c[k] is not None]
        items[k] = ({"scores": sc, "media": round(st.mean(sc), 1),
                     "sd": round(st.pstdev(sc), 1), "min": min(sc), "max": max(sc),
                     "rango": max(sc) - min(sc)} if sc else None)
    arqs = Counter(c["arquetipo"] for c in cs if c["arquetipo"])
    moda, nmoda = (arqs.most_common(1)[0] if arqs else (None, 0))
    llamadas.append({"id8": m["meeting_id"][:8], "lead": m["lead"], "fecha": m["fecha"],
                     "punto": m["punto"], "n_tiradas": len(cs), "tiradas": tiradas,
                     "items": items,
                     "arquetipos": {"distintos": len(arqs), "moda": moda,
                                    "consenso": round(nmoda / len(cs), 2) if cs else None,
                                    "conteo": dict(arqs)}})

# Descomposición señal/ruido por ítem — ANOVA de un factor (llamada).
por_item = []
con = [L for L in llamadas if L["n_tiradas"] >= 2]
for k in ITEMS:
    grupos = [L["items"][k]["scores"] for L in con if L["items"][k]]
    if len(grupos) < 2:
        continue
    todos = [x for g in grupos for x in g]
    gm = st.mean(todos)
    k0 = st.mean([len(g) for g in grupos])
    msw_num = sum(sum((x - st.mean(g)) ** 2 for x in g) for g in grupos)
    msw_den = sum(len(g) - 1 for g in grupos)
    msw = msw_num / msw_den if msw_den else 0.0
    msb = sum(len(g) * (st.mean(g) - gm) ** 2 for g in grupos) / (len(grupos) - 1)
    icc = max(0.0, (msb - msw) / (msb + (k0 - 1) * msw)) if (msb + (k0 - 1) * msw) else 0.0
    sd_intra = msw ** 0.5
    por_item.append({
        "item": k,
        "sd_intra": round(sd_intra, 1),                # el ruido del proceso
        "sd_inter": round(max(0.0, (msb - msw) / k0) ** 0.5, 1),  # la señal entre leads
        "icc": round(icc, 2),
        "rango_medio": round(st.mean([L["items"][k]["rango"] for L in con if L["items"][k]]), 1),
        # dos corridas sueltas difieren menos que esto el 95% de las veces
        "diferencia_minima_detectable": round(2.77 * sd_intra, 1),
    })

def lectura(icc):
    if icc >= 0.90: return "excelente"
    if icc >= 0.75: return "buena"
    if icc >= 0.50: return "moderada"
    return "pobre — el ruido domina"

out = {
    "llamadas": llamadas,
    "por_item": por_item,
    "global": {
        "n_llamadas": len(llamadas),
        "n_tiradas": sum(L["n_tiradas"] for L in llamadas),
        "prompt": "mejorado2", "modelo": "claude-opus-5",
        "semilla_muestreo": "20260809",
        "lectura_icc": {p["item"]: lectura(p["icc"]) for p in por_item},
        "nota": ("ICC = fracción de la varianza que es del LEAD y no de la tirada. "
                 "diferencia_minima_detectable = 2.77·sd_intra: dos leads cuyos puntajes "
                 "de UNA corrida difieren menos que eso son indistinguibles del azar."),
    },
}
print(json.dumps(out, ensure_ascii=False, indent=None if len(sys.argv) > 2 else 1))
PY
