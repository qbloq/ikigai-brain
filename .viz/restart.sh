#!/usr/bin/env bash
# Restart the viz server: stop any running instance, relaunch detached.
# Node caches required modules, so after editing .viz/ you must restart to pick
# up changes (new datasources, components, etc.).
#
# Usage:  bash .viz/restart.sh        (or: npm run viz:restart)
#         PORT=4318 bash .viz/restart.sh
set -euo pipefail

PORT="${PORT:-4317}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/.viz/viz.log"

# --- stop any running instance ---------------------------------------------
# Match by the LISTENER on our PORT, not by command-line text: a `pkill -f
# .viz/server.js` would also kill any unrelated shell whose command merely
# mentions ".viz/server.js" (e.g. an ad-hoc `pgrep`/`node -c`), including the
# caller. Port ownership is unambiguous.
port_pids() { { command -v fuser >/dev/null 2>&1 && fuser -n tcp "$PORT" 2>/dev/null; } \
  || { command -v lsof >/dev/null 2>&1 && lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null; }; }
pids="$(port_pids | tr -s ' ' '\n' | grep -E '^[0-9]+$' || true)"
if [[ -n "$pids" ]]; then
  echo "stopping viz on :$PORT (pid: $(echo "$pids" | tr '\n' ' '))"
  kill $pids 2>/dev/null || true
  sleep 0.5
  kill -9 $(port_pids) 2>/dev/null || true
fi

# --- relaunch detached ------------------------------------------------------
cd "$REPO_ROOT"
PORT="$PORT" nohup node .viz/server.js >"$LOG" 2>&1 &
newpid=$!
disown 2>/dev/null || true
sleep 0.9

if kill -0 "$newpid" 2>/dev/null; then
  echo "viz on http://localhost:$PORT (pid $newpid) — log: .viz/viz.log"
else
  echo "viz failed to start; last log lines:" >&2
  tail -n 20 "$LOG" >&2 || true
  exit 1
fi
