#!/usr/bin/env bash
# analitica.sh — funnel de video (impresiones→plays→retención→pitch→fin→CTA), en vivo.
#
# Per video: POST /sessions/stats (device-unique counts, date-windowed) and
# POST /times/user_engagement (requires the video's duration as an INPUT —
# taken from the stored selection, or --duracion).
#
# ⚠️ Semántica verificada 2026-08-20 contra datos reales:
#   - `total_viewed_*` son IMPRESIONES del player (siempre ≥ plays);
#     `total_started_*` son los plays. play_rate = started/viewed.
#   - `grouped_timed` NO es curva de supervivencia: es un HISTOGRAMA de dónde
#     paró cada espectador (suma ≈ plays de la ventana; el bucket duración+1
#     son los que terminaron). Retención en t = suma de buckets ≥ t / total.
#     Prueba: el promedio reconstruido del histograma reproduce exactamente el
#     `average_watched_time` del API. (El normalizador de Marketico lo lee
#     como supervivencia — bug reportable: su retención de funnel sale rota.)
#   - La ventana de fechas SÍ aplica también al engagement (la suma del
#     histograma calza con los plays de la ventana, no con el all-time).
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Uso: analitica.sh --project NOMBRE [--video ID [--duracion S]]
                  [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--json]

Funnel VTurb de los videos SELECCIONADOS del proyecto (o de uno con --video):
  impresiones · plays · tasa de play · retención 25/50/75% · % terminó ·
  % pasó el pitch · clicks CTA · duración
(conteos device-unique; retención = % de los plays que seguía viendo en ese
punto, calculada del histograma de abandono de VTurb)

Ventana default: mes actual (America/Bogota). Fechas enviadas a VTurb con
timezone America/Bogota; la ventana aplica a TODO (verificado, ver header).

--video ID     Un solo video (player id). Si no está en las selecciones, la
               duración no se conoce — pásala con --duracion (segundos).

Un video que falla se reporta a stderr y no tumba el resto.

Solo lee. El token sale de project_vturb_video_configs y nunca se imprime.
EOF
}

project=""; video=""; duracion=""; from=""; to=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --video) video="$2"; shift 2 ;;
    --duracion) duracion="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    --to) to="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$project" ]] && { echo "vturb: falta --project (proyectos: $(vturb_projects | cut -f2 | paste -sd', '))" >&2; exit 2; }

IFS=$'\t' read -r pid pname < <(vturb_resolve_project "$project")
IFS=$'\t' read -r w_from w_to < <(vturb_window "$from" "$to")
sels="$(vturb_selections "$pid")"

# Target list: [{video_id, titulo, duracion}] — selections, or the one --video.
targets="$(python3 -c '
import json, sys
sels, video, dur = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3]
if video:
    match = next((s for s in sels if s["video_id"] == video), None)
    if match:
        if dur: match["duracion"] = int(dur)
        out = [match]
    else:
        out = [{"video_id": video, "titulo": "(no seleccionado)", "duracion": int(dur) if dur else 0}]
else:
    out = sels
json.dump(out, sys.stdout, ensure_ascii=False)' "$sels" "$video" "$duracion")"

if [[ "$targets" == "[]" ]]; then
  echo "vturb: el proyecto '$pname' no tiene videos seleccionados (ver videos.sh)." >&2
  exit 1
fi

vturb_load_creds "$pid"

results="[]"
while IFS=$'\t' read -r vid titulo dur; do
  [[ -z "$vid" ]] && continue
  body_stats="$(python3 -c '
import json, sys
json.dump({"player_id": sys.argv[1], "start_date": sys.argv[2], "end_date": sys.argv[3], "timezone": sys.argv[4]}, sys.stdout)' \
    "$vid" "$w_from" "$w_to" "$VTURB_TZ")"
  if ! stats="$(vturb_api_post "/sessions/stats" "$body_stats")"; then
    echo "vturb: fallo /sessions/stats para '$titulo' ($vid) — se omite." >&2
    continue
  fi
  body_ret="$(python3 -c '
import json, sys
json.dump({"player_id": sys.argv[1], "video_duration": int(sys.argv[2] or 0), "start_date": sys.argv[3], "end_date": sys.argv[4], "timezone": sys.argv[5]}, sys.stdout)' \
    "$vid" "$dur" "$w_from" "$w_to" "$VTURB_TZ")"
  ret="$(vturb_api_post "/times/user_engagement" "$body_ret")" || {
    echo "vturb: fallo /times/user_engagement para '$titulo' ($vid) — retención vacía." >&2
    ret='{}'
  }
  results="$(python3 -c '
import json, sys
results = json.loads(sys.argv[1])
vid, titulo, dur = sys.argv[2], sys.argv[3], int(sys.argv[4] or 0)
stats, ret = json.loads(sys.argv[5]), json.loads(sys.argv[6])

impresiones = int(stats.get("total_viewed_device_uniq") or 0)
plays       = int(stats.get("total_started_device_uniq") or 0)
termino     = int(stats.get("total_finished_device_uniq") or 0)
cta         = int(stats.get("total_clicked_device_uniq") or 0)
over_pitch  = int(stats.get("total_over_pitch") or 0)

# grouped_timed = stop-time histogram (see header). Retention at t is the
# cumulative tail: users whose stop point is >= t, over the histogram total.
hist = sorted(
    ({"segundo": int(p["timed"]), "usuarios_pararon": int(p.get("total_users") or 0)}
     for p in (ret.get("grouped_timed") or []) if str(p.get("timed", "")).lstrip("-").isdigit() and int(p["timed"]) >= 0),
    key=lambda p: p["segundo"])
total_hist = sum(p["usuarios_pararon"] for p in hist)

def ret_pct(pct):
    if not hist or not dur or not total_hist: return None
    t = dur * pct / 100
    alive = sum(p["usuarios_pararon"] for p in hist if p["segundo"] >= t)
    return round(100 * alive / total_hist, 1)

pc = lambda num, den: round(100 * num / den, 1) if den else None
results.append({
    "video_id": vid, "titulo": titulo, "duracion": dur or None,
    "impresiones_unicas": impresiones, "plays_unicos": plays,
    "tasa_play": pc(plays, impresiones),
    "ret_25": ret_pct(25), "ret_50": ret_pct(50), "ret_75": ret_pct(75),
    "terminaron": termino, "tasa_fin": pc(termino, plays),
    "pasaron_pitch": over_pitch, "tasa_pitch": pc(over_pitch, plays),
    "cta_clicks": cta,
    "avg_visto_seg": ret.get("average_watched_time"),
    "engagement_rate": ret.get("engagement_rate"),
    "histograma_abandono": hist,
})
json.dump(results, sys.stdout, ensure_ascii=False)' \
    "$results" "$vid" "$titulo" "$dur" "$stats" "$ret")"
done < <(python3 -c '
import json, sys
for t in json.loads(sys.argv[1]):
    print("%s\t%s\t%s" % (t["video_id"], t["titulo"], t.get("duracion") or 0))' "$targets")

if [[ "$FORMAT" == "json" ]]; then
  python3 -c '
import json, sys
json.dump({"proyecto": sys.argv[1], "ventana": {"from": sys.argv[2], "to": sys.argv[3], "timezone": sys.argv[4]},
           "nota": "conteos device-unique; retencion = cola acumulada del histograma de abandono (usuarios que pararon en o despues de t / total)",
           "videos": json.loads(sys.argv[5])}, sys.stdout, ensure_ascii=False)' \
    "$pname" "$w_from" "$w_to" "$VTURB_TZ" "$results"
  echo
else
  echo "Proyecto: $pname · ventana $w_from → $w_to ($VTURB_TZ)"
  echo "(device-unique · tasa_play = plays/impresiones · ret_N = % de plays que seguía viendo al N% de la duración · pitch/fin sobre plays)"
  printf '%s' "$results" | vturb_render 'titulo:titulo,impr:impresiones_unicas,plays:plays_unicos,play_pct:tasa_play,ret_25:ret_25,ret_50:ret_50,ret_75:ret_75,fin_pct:tasa_fin,pitch_pct:tasa_pitch,cta:cta_clicks,dur_s:duracion'
fi
