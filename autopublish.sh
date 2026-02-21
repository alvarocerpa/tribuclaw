#!/bin/bash
# autopublish.sh — Publica 1-2 posts/día en horarios naturales
#
# Cron (2 ventanas por día):
#   0 8 * * *  → Ventana mañana (8:00-12:00)
#   0 15 * * * → Ventana tarde  (15:00-19:00)
#
# Cada ventana: ~65% de probabilidad de publicar
# → Esperado: ~1.3 posts/día | Máx: 2/día

LOG="/tmp/autopublish.log"
DEPLOY_SCRIPT="/home/claw1/.openclaw/workspace/tribuclaw-web/autopublish-deploy.sh"
LOCK_FILE="/tmp/autopublish.lock"
DAY_COUNT_FILE="/tmp/autopublish-day-$(date +%Y%m%d).count"

echo "$(date '+%Y-%m-%d %H:%M') — autopublish triggered" >> "$LOG"

# Evitar ejecuciones paralelas
if [[ -f "$LOCK_FILE" ]]; then
  echo "  → Deploy en curso (lock activo). Saltando." >> "$LOG"
  exit 0
fi

# Máximo 2 posts por día
POSTS_HOY=0
[[ -f "$DAY_COUNT_FILE" ]] && POSTS_HOY=$(cat "$DAY_COUNT_FILE")
if [[ "$POSTS_HOY" -ge 2 ]]; then
  echo "  → Ya publicamos 2 posts hoy. Saltando." >> "$LOG"
  exit 0
fi

# Probabilidad ~65% usando /dev/urandom (10 valores → publicar si ≤6)
RAND=$(( $(od -An -N1 -tu1 /dev/urandom | tr -d ' ') % 10 ))
echo "  Rand 0-9: $RAND (publica si ≤ 6)" >> "$LOG"

if [[ "$RAND" -le 6 ]]; then
  # Delay aleatorio entre 5 min y 4h para no publicar siempre a :00
  # Esto hace que la hora exacta varíe cada día (7:08, 8:43, 7:31...)
  DELAY=$(( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 14400 + 300 ))
  HORA_EST=$(date -d "+${DELAY} seconds" '+%H:%M' 2>/dev/null || date '+%H:%M')
  echo "  → Sí publica. Delay: ${DELAY}s (~${HORA_EST}). Lanzando en background." >> "$LOG"

  touch "$LOCK_FILE"
  NUEVO_COUNT=$(( POSTS_HOY + 1 ))

  nohup bash -c "
    sleep $DELAY
    bash '$DEPLOY_SCRIPT' >> '$LOG' 2>&1
    echo $NUEVO_COUNT > '$DAY_COUNT_FILE'
    rm -f '$LOCK_FILE'
  " > /dev/null 2>&1 &
  disown
else
  echo "  → No publica en esta ventana (rand=$RAND)" >> "$LOG"
fi
