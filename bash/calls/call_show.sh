#!/usr/bin/env bash
# Full detail of ONE sales call: header (lead, program, project, closer,
# resultado, probabilidad, score) + the analysis report rendered section by
# section — general metrics, call structure (5 fases), final closer evaluation
# (fortalezas / mejoras / coaching), objection handling, critical moments,
# lead profile (BANT, arquetipo, predicciones) and marketing insights.
#
# Usage: call_show.sh <id|prefix> [--json]
#   <id|prefix>  meeting id (UUID prefix ok, e.g. from calls.sh)
#   --json       one JSON object: {header fields..., report: <raw jsonb>}
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) id="$1"; shift ;;
  esac
done
[[ -n "$id" ]] || { echo "Usage: call_show.sh <id|prefix> [--json]" >&2; exit 2; }

json="$(psql_ro -t -A <<SQL
SELECT jsonb_build_object(
  'id', m.id,
  'name', m.name,
  'start', to_char(m.scheduled_start_time,'YYYY-MM-DD HH24:MI'),
  'status', m.status,
  'project', pr.name,
  'closer', cl.closer,
  'lead', coalesce(r.report->'generalInformation'->>'leadName', split_part(m.name,' - ',1)),
  'program', coalesce(r.report->'generalInformation'->>'program', split_part(m.name,' - ',2)),
  'result', r.report->'generalInformation'->>'callStatus',
  'payment_date', r.report->'generalInformation'->>'paymentDate',
  'prob', r.report->'leadProfile'->'predictionsAndRecommendations'->'closingProbability'->>'percentage',
  'score', r.report->'performanceInsights'->'finalCloserEvaluation'->>'overallScore',
  'has_transcript', EXISTS (SELECT 1 FROM meeting_transcripts x WHERE x.meeting_id=m.id),
  'report', r.report
)
FROM meetings m
LEFT JOIN projects pr ON pr.id=m.project_id
LEFT JOIN meeting_reports r ON r.meeting_id=m.id
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
WHERE m.meeting_type='call' AND m.id::text LIKE '${id//\'/}%'
ORDER BY m.scheduled_start_time DESC
LIMIT 1
SQL
)"
[[ -n "$json" ]] || { echo "No sales call matches: $id" >&2; exit 1; }

if [[ "$FORMAT" == "json" ]]; then
  printf '%s\n' "$json"
  exit 0
fi

# The heredoc feeds python its SCRIPT via stdin, so the data travels as argv.
python3 - "$json" <<'PY'
import json, sys, textwrap

d = json.loads(sys.argv[1])
rep = d.get("report") or {}

def line(label, v):
    if v not in (None, ""): print(f"  {label:<12} {v}")

def sec(title):
    print(f"\n== {title} " + "=" * max(0, 56 - len(title)))

def wrap(text, indent="  ", width=94):
    for ln in textwrap.wrap(str(text), width=width) or [""]:
        print(indent + ln)

print(f"LLAMADA {str(d.get('id'))[:8]} · {d.get('name') or ''}")
line("Fecha", d.get("start")); line("Estado", d.get("status"))
line("Lead", d.get("lead")); line("Programa", d.get("program")); line("Proyecto", d.get("project"))
line("Closer", d.get("closer") or "— (sin resolver: revisar opportunity/user en CRM)")
line("Resultado", d.get("result")); line("Prob. cierre", (d.get("prob") or "") and f"{d.get('prob')}%")
line("Score closer", (d.get("score") or "") and f"{d.get('score')}/10")
line("Pago", d.get("payment_date")); line("Transcript", "sí" if d.get("has_transcript") else "no")

if not rep:
    print("\n(Esta llamada no tiene reporte de análisis.)"); raise SystemExit

gm = rep.get("generalMetrics") or []
if gm:
    sec("Métricas generales")
    for x in gm: print(f"  {x.get('metric','—'):<38} {x.get('result','—')}")

cs = (rep.get("performanceInsights") or {}).get("callStructure") or {}
if cs:
    sec("Estructura de la llamada")
    for k, label in [("initialRapport","Rapport"),("frameSetting","Frame"),("qualification","Calificación"),
                     ("programPresentation","Presentación"),("closing","Cierre")]:
        if cs.get(k):
            print(f"  · {label}:"); wrap(cs[k], "      ")

fe = (rep.get("performanceInsights") or {}).get("finalCloserEvaluation") or {}
if fe:
    score = fe.get("overallScore")
    sec(f"Evaluación del closer{f' · {score}/10' if score not in (None, '') else ''}")
    for key, label in [("strengths","Fortalezas"),("areasForImprovement","Áreas de mejora")]:
        items = (fe.get(key) or {}).get("items") or []
        if items:
            print(f"  {label}:")
            for it in items: wrap(f"– {it}", "    ")
    coach = fe.get("coachingRecommendation") or []
    if coach:
        print("  Coaching:")
        for it in (coach if isinstance(coach, list) else [coach]): wrap(f"– {it}", "    ")

oh = (rep.get("objectionsAndInsights") or {}).get("objectionHandling") or {}
objs = oh.get("objections") or []
if oh.get("summary") or objs:
    sec("Objeciones")
    if oh.get("summary"): wrap(oh["summary"])
    for o in objs:
        print(f"  [{o.get('status','?')}]"); wrap(o.get("objection",""), "    ")
        if o.get("closerResponse"): wrap(f"closer → {o['closerResponse']}", "      ")
        if o.get("aiSuggestion"): wrap(f"IA → {o['aiSuggestion']}", "      ")

cm = ((rep.get("performanceInsights") or {}).get("sentimentAndEmotionAnalysis") or {}).get("criticalMomentsDetected") or []
if cm:
    sec("Momentos críticos")
    for x in cm: print(f"  {x.get('timestamp','—'):<7} [{x.get('severity','?')}] {x.get('momentName','')}")

lp = rep.get("leadProfile") or {}
bant = lp.get("bantAnalysis") or {}
seg = lp.get("intelligentSegmentation") or {}
pred = lp.get("predictionsAndRecommendations") or {}
if bant or seg or pred:
    sec("Perfil del lead")
    if bant:
        scores = " · ".join(f"{k.capitalize()} {v.get('score','?')}" for k, v in bant.items() if isinstance(v, dict))
        print(f"  BANT: {scores}")
    arch = (seg.get("archetype") or {}).get("name")
    if arch: line("Arquetipo", arch)
    pc = seg.get("priorityClassification") or {}
    if pc.get("priority"): line("Prioridad", pc.get("priority"))
    if pred.get("recommendedOfferType"): line("Oferta sug.", pred.get("recommendedOfferType"))
    strat = pred.get("recommendedClosingStrategy") or []
    if strat:
        print("  Estrategia recomendada:")
        for s in (strat if isinstance(strat, list) else [strat]): wrap(f"– {s}", "    ")

mi = (rep.get("performanceInsights") or {}).get("marketingInsights") or {}
if mi:
    sec("Insights de marketing (feedback a narrativas)")
    for k, label in [("leadQuality","Calidad del lead"),("recommendations","Recomendación"),("suggestedAction","Acción sugerida")]:
        if mi.get(k):
            print(f"  {label}:"); wrap(mi[k], "    ")

if rep.get("aiAgentConclusion"):
    sec("Conclusión del agente")
    wrap(rep["aiAgentConclusion"])
PY
