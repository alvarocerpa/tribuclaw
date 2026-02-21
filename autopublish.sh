#!/bin/bash
# autopublish.sh — Decide aleatoriamente si publica hoy y lanza el deploy
# Cron: 0 7,9,11,13,15,17,19,21 * * *
# Probabilidad ~20% por ejecución → ~1-2 posts/día

LOG="/tmp/autopublish.log"
DEPLOY_SCRIPT="/home/claw1/.openclaw/workspace/tribuclaw-web/autopublish-deploy.sh"
LOCK_FILE="/tmp/autopublish.lock"

echo "$(date '+%Y-%m-%d %H:%M') — autopublish triggered" >> "$LOG"

# Evitar ejecuciones paralelas
if [[ -f "$LOCK_FILE" ]]; then
  echo "  → Ya hay un deploy en curso (lock activo). Saltando." >> "$LOG"
  exit 0
fi

# Aleatoriedad 1-7 usando /dev/urandom (RANDOM no funciona bien en cron)
RANDOM_DAY=$(( $(od -An -N1 -tu1 /dev/urandom | tr -d ' ') % 7 + 1 ))
echo "  Random 1-7: $RANDOM_DAY" >> "$LOG"

if [ "$RANDOM_DAY" -eq 1 ]; then
  DELAY=$(( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 3600 + 300 ))
  echo "  → Sí publica. Delay: ${DELAY}s. Lanzando en background." >> "$LOG"
  touch "$LOCK_FILE"
  # nohup + disown garantiza que el proceso sobrevive al fin de sesión cron
  nohup bash -c "sleep $DELAY && bash '$DEPLOY_SCRIPT' >> '$LOG' 2>&1 && rm -f '$LOCK_FILE'" > /dev/null 2>&1 &
  disown
else
  echo "  → No publica hoy (salió $RANDOM_DAY)" >> "$LOG"
fi

echo "---" >> "$LOG"
