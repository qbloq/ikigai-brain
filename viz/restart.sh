#!/usr/bin/env bash
# Restart the viz server: stop any running instance, relaunch detached.
# Node caches required modules, so after editing viz/ you must restart to pick
# up changes (new datasources, components, etc.).
#
# Usage:  bash viz/restart.sh        (or: npm run viz:restart)
#         PORT=4318 bash viz/restart.sh
set -euo pipefail

PORT="${PORT:-4317}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/viz/viz.log"

# --- stop any running instance ---------------------------------------------
pids="$(pgrep -f 'viz/server.js' || true)"
if [[ -n "$pids" ]]; then
  echo "stopping viz (pid: $(echo "$pids" | tr '\n' ' '))"
  kill $pids 2>/dev/null || true
  sleep 0.5
  pkill -9 -f 'viz/server.js' 2>/dev/null || true
fi

# --- relaunch detached ------------------------------------------------------
cd "$REPO_ROOT"
PORT="$PORT" nohup node viz/server.js >"$LOG" 2>&1 &
newpid=$!
disown 2>/dev/null || true
sleep 0.9

if kill -0 "$newpid" 2>/dev/null; then
  echo "viz on http://localhost:$PORT (pid $newpid) — log: viz/viz.log"
else
  echo "viz failed to start; last log lines:" >&2
  tail -n 20 "$LOG" >&2 || true
  exit 1
fi
