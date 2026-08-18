#!/usr/bin/env bash
# Hook de SessionStart — el copiloto se actualiza solo al despertar.
#
# Diseño (validado con la prueba real del fork de lorenzo, 2026-08-18):
#   · Solo actúa en COPILOTOS (existe copilot.json); en el cerebro es un no-op.
#   · Throttle: a lo sumo un chequeo cada 4 horas (sello en .git/) — reabrir
#     sesiones no paga latencia de red.
#   · El laptop sigue a SU bare (origin) — un solo punto de rebase (45d49ad);
#     sana la topología vieja de los forks pre-agosto en cada corrida.
#   · Fail-soft SIEMPRE: sin red → silencio; conflicto → abort + nota; el
#     arranque de la sesión jamás se bloquea (exit 0 en todos los caminos).
#   · Lo que imprime a stdout entra como contexto de la sesión que arranca —
#     una línea, para que el copiloto sepa qué pasó y lo cuente natural.
#   · El orden de la carpeta (chflags) es utilería MUDA: jamás se narra.
#
# Gemelo manual: .claude/skills/actualizarse (la palabra «actualízate»).
set -u
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
[ -f copilot.json ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

STAMP=".git/ultima-actualizacion"
AHORA=$(date +%s)
if [ -f "$STAMP" ]; then
  ANTES_TS=$(cat "$STAMP" 2>/dev/null || echo 0)
  case "$ANTES_TS" in (*[!0-9]*) ANTES_TS=0;; esac
  [ $((AHORA - ANTES_TS)) -lt 14400 ] && exit 0
fi
echo "$AHORA" > "$STAMP" 2>/dev/null || true

# Topología: el laptop sigue a SU bare (idempotente; sana forks pre-agosto).
git config branch.main.remote origin 2>/dev/null || true
git config branch.main.merge refs/heads/main 2>/dev/null || true
git config branch.main.pushRemote origin 2>/dev/null || true

git fetch -q origin 2>/dev/null || exit 0   # sin red: silencio total

antes=$(git rev-parse HEAD 2>/dev/null) || exit 0
atras=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)

if [ "$atras" -gt 0 ]; then
  if git rebase -q origin/main >/dev/null 2>&1; then
    git push -q origin main >/dev/null 2>&1 || true
    # Orden de la carpeta (macOS; en otros SO falla en silencio). MUDO.
    chflags hidden bash viz docs bin lib data CLAUDE.md cerebro.json copilot.json package.json tema.json .gitignore 2>/dev/null || true
    n=$(git rev-list --count "$antes"..HEAD 2>/dev/null || echo "$atras")
    echo "[actualizacion-automatica] Te actualizaste al despertar: $n novedad(es) del cerebro (git log ${antes}..HEAD). Si viene al caso, cuéntale a tu humano en su idioma qué puede hacer ahora que antes no — jamás menciones el orden de archivos ni jerga git."
  else
    git rebase --abort >/dev/null 2>&1 || true
    echo "[actualizacion-automatica] Intenté actualizarme al despertar pero hay un conflicto que no debo resolver solo. Cuando venga al caso, pídele a tu humano que le avise a Santiago (Parallelo)."
  fi
else
  # Al día con el cerebro — respaldo silencioso de lo personal, si hay.
  git push -q origin main >/dev/null 2>&1 || true
fi
exit 0
