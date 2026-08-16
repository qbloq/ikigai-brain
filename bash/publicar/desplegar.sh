#!/usr/bin/env bash
# desplegar.sh [--dry-run]   [WRITE remoto]
# Lleva el código al publicador: push a origin, pull en /apps/hermetico y
# restart de pm2 viz-publish. Para cambios de CÓDIGO; el registro no lo toca.
# Compara el sha remoto contra el empujado: un pull que no trae nada es un
# deploy que no despliega, y sin esto no hacía ruido.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -4; exit 0; }

RAMA="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
if [[ $DRY -eq 1 ]]; then
  echo "[dry-run] git push origin $RAMA && ssh $PUB_SSH 'cd $PUB_DIR && git pull --ff-only && pm2 restart viz-publish --update-env && git rev-parse HEAD'"
  echo "[dry-run] luego: comparar ese sha contra $(git -C "$REPO_ROOT" rev-parse HEAD) y gritar si difieren"
  exit 0
fi
git -C "$REPO_ROOT" push origin "$RAMA"
LOCAL_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
REMOTE_SHA="$(ssh "$PUB_SSH" "cd '$PUB_DIR' && git pull --ff-only >&2 && pm2 restart viz-publish --update-env >&2 && git rev-parse HEAD")"

# El pull remoto puede tener éxito y NO traer nada: si el checkout está en otra
# rama (o la sigue por otro remoto), `git pull --ff-only` responde «Already
# up to date» y pm2 reinicia el código VIEJO — un deploy que no despliega, en
# silencio. La única prueba de que el código llegó es el sha.
if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
  echo "" >&2
  echo "⚠️  ATENCIÓN: el remoto NO quedó en el commit que acabás de empujar." >&2
  echo "    local  ($RAMA): $LOCAL_SHA" >&2
  echo "    remoto ($PUB_SSH:$PUB_DIR): $REMOTE_SHA" >&2
  echo "    El pull no falló, pero no trajo esto — típicamente el checkout remoto" >&2
  echo "    está en otra rama. Revisá antes de dar el deploy por hecho." >&2
  echo "" >&2
fi

sleep 1
ssh "$PUB_SSH" "curl -sf http://127.0.0.1:4318/health" && echo " ← viz-publish vivo ($REMOTE_SHA)"
