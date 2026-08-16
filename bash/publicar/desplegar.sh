#!/usr/bin/env bash
# desplegar.sh [--dry-run]   [WRITE remoto]
# Lleva el código al publicador: push a origin, pull en /apps/hermetico y
# restart de pm2 viz-publish. Para cambios de CÓDIGO; el registro no lo toca.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -4; exit 0; }

RAMA="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
if [[ $DRY -eq 1 ]]; then
  echo "[dry-run] git push origin $RAMA && ssh $PUB_SSH 'cd $PUB_DIR && git pull --ff-only && pm2 restart viz-publish --update-env'"
  exit 0
fi
git -C "$REPO_ROOT" push origin "$RAMA"
ssh "$PUB_SSH" "cd '$PUB_DIR' && git pull --ff-only && pm2 restart viz-publish --update-env"
sleep 1
ssh "$PUB_SSH" "curl -sf http://127.0.0.1:4318/health" && echo " ← viz-publish vivo"
