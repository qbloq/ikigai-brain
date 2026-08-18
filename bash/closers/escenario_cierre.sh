#!/usr/bin/env bash
# [WRITE → WhatsApp] Escenario 5 — cierre del día (20:00 COT, cron): a cada
# closer que tuvo llamadas hoy o tiene cuotas venciendo mañana le llega:
#
#   1. Sus VENTAS y demás resultados del día — leídos de la memoria de Iki
#      (brain.db, solo lectura: filas `RESULTADO: <fecha> | <closer> | …` que
#      el protocolo post-llamada guarda) + la cola local `resultados`.
#   2. Sus cuotas que vencen MAÑANA (payment_plans.user_id ES el closer) con
#      el total de recaudo posible. Solo las suyas, jamás todas.
#
# Idempotente: ref = <fecha>-<closer>. Sesión con fallback a plantilla.
# Usage: escenario_cierre.sh [--fecha YYYY-MM-DD] [--fallback PLANTILLA] [--dry-run] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/common.sh >/dev/null

FECHA=""; FALLBACK="weekly_report"; DRY=(); FORMAT_OUT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fecha) FECHA="$2"; shift 2 ;;
    --fallback) FALLBACK="$2"; shift 2 ;;
    --dry-run) DRY=(--dry-run); shift ;;
    --json) FORMAT_OUT=json; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$FECHA" ]] && FECHA="$(TZ=America/Bogota date +%F)"
MANANA="$(TZ=America/Bogota date -d "$FECHA + 1 day" +%F)"

AG="$(mktemp)"; CUOTAS="$(mktemp)"; RESU="$(mktemp)"; TSV="$(mktemp)"
trap 'rm -f "$AG" "$CUOTAS" "$RESU" "$TSV"' EXIT

bash bash/closers/agenda.sh --fecha "$FECHA" --json > "$AG"

FORMAT=json emit "SELECT trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')) AS closer,
  coalesce(pp.customer_name,'(cliente)') AS cliente,
  round(i.scheduled_amount - coalesce(i.paid_amount,0))::int AS pendiente
FROM installments i
JOIN payment_plans pp ON pp.plan_id = i.plan_id
JOIN users u ON u.id = pp.user_id
JOIN persons p ON p.person_id = u.person_id
WHERE i.due_date::date = '$MANANA'::date
  AND i.status IN ('Scheduled','Partial','Overdue')
  AND i.scheduled_amount - coalesce(i.paid_amount,0) > 0
ORDER BY 1, 3 DESC" > "$CUOTAS"

# Resultados del día: memoria de Iki (solo lectura) + cola local.
BRAIN="$HOME/.zeroclaw/data/memory/brain.db"
{
  [[ -f "$BRAIN" ]] && sqlite3 -readonly "$BRAIN" \
    "SELECT content FROM memories WHERE content LIKE 'RESULTADO: $FECHA%'" 2>/dev/null
  OPS="$REPO_ROOT/data/sqlite/closers_ops.db"
  [[ -f "$OPS" ]] && sqlite3 -readonly "$OPS" \
    "SELECT 'RESULTADO: '||fecha||' | '||closer||' | '||coalesce(lead,'')||' | '||resultado||' | '||coalesce(detalle,'') FROM resultados WHERE fecha='$FECHA'" 2>/dev/null
} | sort -u > "$RESU" || true

AG="$AG" CUOTAS="$CUOTAS" RESU="$RESU" FECHA="$FECHA" MANANA="$MANANA" python3 - > "$TSV" <<'PY'
import json, os, collections, unicodedata
NL = "\\n"

def norm(s):
    return unicodedata.normalize("NFKD", (s or "").lower()).encode("ascii", "ignore").decode()

agenda = json.load(open(os.environ["AG"]))
cuotas = json.load(open(os.environ["CUOTAS"]))
llamadas = collections.Counter(r["closer"] for r in agenda if r.get("closer"))

resultados = collections.defaultdict(list)
for line in open(os.environ["RESU"]):
    partes = [p.strip() for p in line.strip().split("|")]
    if len(partes) >= 4:
        closer, lead, res = partes[1], partes[2], partes[3]
        resultados[norm(closer)].append((lead, res.lower()))

cuotas_por = collections.defaultdict(list)
for c in cuotas:
    cuotas_por[c["closer"]].append(c)

todos = set(llamadas) | {c["closer"] for c in cuotas}
for closer in sorted(todos):
    nombre = closer.split()[0]
    partes = [f"{nombre}, cierre del día 📋"]
    res = resultados.get(norm(closer), [])
    ventas = [l for l, r in res if "venta" in r]
    if res:
        otros = collections.Counter(r for _, r in res if "venta" not in r)
        linea = f"Ventas de hoy: *{len(ventas)}*"
        if ventas: linea += f" ({', '.join(ventas)})"
        if otros: linea += " — " + ", ".join(f"{n} {r}" for r, n in otros.items())
        partes.append(linea)
    elif llamadas.get(closer):
        partes.append(f"Tuviste {llamadas[closer]} llamada(s) hoy y no tengo resultados registrados — cuéntame cómo te fue.")
    cs = cuotas_por.get(closer, [])
    if cs:
        total = sum(c["pendiente"] for c in cs)
        det = " · ".join(f"{c['cliente']} ${c['pendiente']:,}" for c in cs[:6])
        partes.append(f"Cuotas tuyas que vencen mañana: {det} — recaudo posible: *${total:,}*")
    else:
        partes.append("Mañana no se te vence ninguna cuota.")
    print("\t".join([closer, NL.join(partes)]))
PY

RES=()
while IFS=$'\t' read -r closer cuerpo; do
  [[ -z "$closer" ]] && continue
  cuerpo="${cuerpo//\\n/$'\n'}"
  out="$(bash bash/closers/enviar.sh --para "$closer" --closer "$closer" \
    --texto "$cuerpo" --fallback-plantilla "$FALLBACK" \
    --escenario cierre --ref "$FECHA-${closer// /_}" --json "${DRY[@]}" || true)"
  RES+=("{\"closer\":\"$closer\",\"envio\":${out:-null}}")
done < "$TSV"

if [[ "$FORMAT_OUT" == json ]]; then
  printf '[%s]\n' "$(IFS=,; echo "${RES[*]:-}")"
else
  for r in "${RES[@]:-}"; do echo "$r"; done
  [[ ${#RES[@]} -eq 0 ]] && echo "Nadie con llamadas hoy ni cuotas mañana."
fi
exit 0
