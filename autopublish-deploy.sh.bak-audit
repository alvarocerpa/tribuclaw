#!/bin/bash
# autopublish-deploy.sh — Build + Deploy a Cloudflare Pages
# Llamado por autopublish.sh cuando toca publicar

CF_TOKEN="4fZu4AsXIRUwWWuHJjw2bas66OyHOSNO_aC4wuyh"
CF_ACCOUNT_ID="014162b37ae770253f6e43c0ba038fdb"
CF_PROJECT="tribuclaw"
BLOG_DIR="/home/claw1/.openclaw/workspace/tribuclaw-web"
LOG="/home/claw1/.openclaw/workspace/tribuclaw-web/autopublish-deploy.log"

cd "$BLOG_DIR" || exit 1

echo "[$(date)] ── AUTOPUBLISH DEPLOY INICIADO ──────────────────" | tee -a "$LOG"

# Build
echo "[$(date)] Build Astro..." | tee -a "$LOG"
npx astro build 2>&1 | tee -a "$LOG"
BUILD_EXIT=${PIPESTATUS[0]}

if [ $BUILD_EXIT -ne 0 ]; then
  echo "[$(date)] ERROR: Build fallido (código $BUILD_EXIT). Abortando." | tee -a "$LOG"
  exit 1
fi
echo "[$(date)] Build OK." | tee -a "$LOG"

# Deploy a Cloudflare Pages
echo "[$(date)] Deploy a Cloudflare Pages..." | tee -a "$LOG"
CLOUDFLARE_API_TOKEN="$CF_TOKEN" \
CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID" \
npx wrangler pages deploy dist \
  --project-name "$CF_PROJECT" \
  --branch master \
  --commit-dirty=true 2>&1 | tee -a "$LOG"
DEPLOY_EXIT=${PIPESTATUS[0]}

if [ $DEPLOY_EXIT -ne 0 ]; then
  echo "[$(date)] ERROR: Deploy fallido (código $DEPLOY_EXIT)." | tee -a "$LOG"
  exit 2
fi

echo "[$(date)] Deploy OK. Blog actualizado en tribuclaw.com" | tee -a "$LOG"

# Ping de indexación Google (si el script existe)
INDEX_SCRIPT="/home/claw1/.openclaw/workspace/scripts/index-blog.sh"
if [[ -f "$INDEX_SCRIPT" ]]; then
  echo "[$(date)] Indexación Google..." | tee -a "$LOG"
  bash "$INDEX_SCRIPT" >> "$LOG" 2>&1
fi

echo "[$(date)] ── PIPELINE COMPLETADO ──────────────────────────" | tee -a "$LOG"
echo "AUTOPUBLISH_DONE" >> "$LOG"
