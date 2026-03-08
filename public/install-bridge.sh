#!/bin/bash
# TribuClaw Bridge Installer v2
# Usage: curl -fsSL https://tribuclaw.com/install-bridge.sh | bash -s -- <setupToken> --user <username> [--full] [--panel-url <url>]
#
# --full: installs OpenClaw + Cortex + Bridge (for new servers)
# --user: target user to install under
# (no flag): installs only Bridge (for existing OpenClaw installations)

set -e

SETUP_TOKEN="$1"
FULL_INSTALL=false
TARGET_USER=""
PANEL_URL=""

# Parse arguments
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --full) FULL_INSTALL=true ;;
    --user) shift; TARGET_USER="$1" ;;
    --panel-url) shift; PANEL_URL="$1" ;;
  esac
  shift 2>/dev/null || true
done

PANEL_URL="${PANEL_URL:-https://app.tribuclaw.com}"
BRIDGE_PORT=18889
BRIDGE_JS_URL="https://tribuclaw.com/bridge-v2.js"

# ─────────────────────────────────────────────────
# If running as root with --user, re-exec as target user
# ─────────────────────────────────────────────────

if [ "$(id -u)" = "0" ] && [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
  # Ensure target user exists
  if ! id "$TARGET_USER" &>/dev/null; then
    if [ "$FULL_INSTALL" = true ]; then
      echo -e "\033[0;34m[INFO]\033[0m  Creando usuario '$TARGET_USER'..."
      useradd -m -s /bin/bash "$TARGET_USER"
      echo -e "\033[0;32m[OK]\033[0m    Usuario '$TARGET_USER' creado"
    else
      echo -e "\033[0;31m[ERROR]\033[0m El usuario '$TARGET_USER' no existe. Créalo primero o usa --full."
      exit 1
    fi
  fi

  echo -e "\033[0;34m[INFO]\033[0m  Instalando bajo el usuario '$TARGET_USER'..."

  # Open bridge port in firewall
  if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow ${BRIDGE_PORT}/tcp >/dev/null 2>&1 && \
      echo -e "\033[0;32m[OK]\033[0m    Puerto ${BRIDGE_PORT} abierto en el firewall" || true
  fi

  # Enable linger for systemd user services
  loginctl enable-linger "$TARGET_USER" 2>/dev/null || true

  # Re-exec as target user
  FULL_FLAG=""
  [ "$FULL_INSTALL" = true ] && FULL_FLAG=" --full"
  sudo -u "$TARGET_USER" -i bash -c "curl -fsSL https://tribuclaw.com/install-bridge.sh | bash -s -- $SETUP_TOKEN --user $TARGET_USER$FULL_FLAG --panel-url $PANEL_URL"
  exit $?
fi

INSTALL_DIR="$HOME/tribuclaw-bridge"
SERVICE_NAME="tribuclaw-bridge"

# ─────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────

info()    { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

# ─────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────

echo ""
echo "  ████████╗██████╗ ██╗██████╗ ██╗   ██╗ ██████╗██╗      █████╗ ██╗    ██╗"
echo "     ██╔══╝██╔══██╗██║██╔══██╗██║   ██║██╔════╝██║     ██╔══██╗██║    ██║"
echo "     ██║   ██████╔╝██║██████╔╝██║   ██║██║     ██║     ███████║██║ █╗ ██║"
echo "     ██║   ██╔══██╗██║██╔══██╗██║   ██║██║     ██║     ██╔══██║██║███╗██║"
echo "     ██║   ██║  ██║██║██████╔╝╚██████╔╝╚██████╗███████╗██║  ██║╚███╔███╔╝"
echo "     ╚═╝   ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝  ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝"
echo ""
echo "  Bridge Installer v2"
if [ "$FULL_INSTALL" = true ]; then
  echo "  Modo: COMPLETO (OpenClaw + Cortex + Bridge)"
else
  echo "  Modo: Solo Bridge (para instalaciones existentes)"
fi
echo "  Panel: $PANEL_URL"
echo ""

# ─────────────────────────────────────────────────
# Validate token
# ─────────────────────────────────────────────────

if [ -z "$SETUP_TOKEN" ]; then
  error "No se proporcionó el token de configuración."
  error "Usa el comando que te proporcionó el panel de TribuClaw."
  exit 1
fi

# ─────────────────────────────────────────────────
# Check dependencies
# ─────────────────────────────────────────────────

info "Comprobando dependencias..."

if ! command -v node &>/dev/null; then
  if [ "$FULL_INSTALL" = true ]; then
    info "Node.js no encontrado. Instalando..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - 2>/dev/null
    sudo apt-get install -y nodejs 2>/dev/null
  else
    error "Node.js no está instalado. Instala Node.js 18+ primero o usa la opción 'Instalación completa'."
    exit 1
  fi
fi

NODE_MAJOR=$(node --version | cut -dv -f2 | cut -d. -f1)
if [ "$NODE_MAJOR" -lt 18 ]; then
  error "Node.js 18+ requerido. Versión actual: $(node --version)"
  exit 1
fi

success "Node.js $(node --version)"

if ! command -v openssl &>/dev/null; then
  error "openssl no encontrado. Instálalo primero."
  exit 1
fi

# ─────────────────────────────────────────────────
# FULL: Install OpenClaw + Cortex
# ─────────────────────────────────────────────────

if [ "$FULL_INSTALL" = true ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "Instalando OpenClaw..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  export PATH="$HOME/.npm-global/bin:$PATH"
  npm config set prefix "$HOME/.npm-global" 2>/dev/null || true

  OPENCLAW_BIN="$HOME/.npm-global/bin/openclaw"
  if [ -x "$OPENCLAW_BIN" ]; then
    warn "OpenClaw ya está instalado: $($OPENCLAW_BIN --version 2>/dev/null || echo 'versión desconocida')"
  else
    info "Instalando OpenClaw..."
    npm install -g openclaw 2>&1 | tail -5
    success "OpenClaw instalado"
  fi

  echo ""
  info "Instalando Cortex (memoria diferencial)..."
  CORTEX_DIR="$HOME/.openclaw/workspace/projects/cortex"
  if [ -d "$CORTEX_DIR/.git" ]; then
    warn "Cortex ya instalado — actualizando..."
    cd "$CORTEX_DIR" && git pull --ff-only 2>/dev/null || true
  else
    mkdir -p "$HOME/.openclaw/workspace/projects"
    git clone https://github.com/alvarocerpa/openclaw-cortex.git "$CORTEX_DIR" 2>&1 | tail -3
    success "Cortex descargado"
  fi
  if [ -f "$CORTEX_DIR/install.sh" ]; then
    cd "$CORTEX_DIR" && bash install.sh 2>&1 | tail -5
    success "Cortex instalado"
  fi
fi

# ─────────────────────────────────────────────────
# Install Bridge v2
# ─────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Instalando TribuClaw Bridge v2 en $INSTALL_DIR..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p "$INSTALL_DIR"

# Write package.json (v2 needs ws for gateway websocket)
cat > "$INSTALL_DIR/package.json" << 'PKGJSON'
{
  "name": "tribuclaw-bridge",
  "version": "2.0.0",
  "description": "TribuClaw Bridge Server v2",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "fastify": "^4.28.1",
    "@fastify/cors": "^9.0.1",
    "@fastify/helmet": "^11.1.1",
    "dotenv": "^16.4.5",
    "ws": "^8.19.0"
  }
}
PKGJSON

# Download Bridge v2 compiled JS
info "Descargando Bridge v2..."
curl -fsSL "$BRIDGE_JS_URL" -o "$INSTALL_DIR/index.js"
if [ ! -s "$INSTALL_DIR/index.js" ]; then
  error "No se pudo descargar el Bridge. Comprueba tu conexión a internet."
  exit 1
fi
success "Bridge v2 descargado ($(wc -c < "$INSTALL_DIR/index.js") bytes)"

# Install npm dependencies
info "Instalando dependencias npm..."
cd "$INSTALL_DIR"
npm install --production --silent 2>&1 | tail -3
success "Dependencias instaladas"

# ─────────────────────────────────────────────────
# Generate token and write .env
# ─────────────────────────────────────────────────

BRIDGE_TOKEN=$(openssl rand -hex 32)

cat > "$INSTALL_DIR/.env" << ENVEOF
BRIDGE_TOKEN=$BRIDGE_TOKEN
BRIDGE_PORT=$BRIDGE_PORT
BRIDGE_TLS=false
ENVEOF
chmod 600 "$INSTALL_DIR/.env"
success "Token generado y configuración guardada"

# ─────────────────────────────────────────────────
# Start Bridge service
# ─────────────────────────────────────────────────

info "Configurando servicio..."

NODE_PATH=$(which node)
BRIDGE_STARTED=false

# Strategy 1: System-level systemd (if we have sudo/root access)
if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
  info "Instalando servicio de sistema..."

  sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << SVCEOF
[Unit]
Description=TribuClaw Bridge
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$INSTALL_DIR
ExecStart=$NODE_PATH $INSTALL_DIR/index.js
Restart=always
RestartSec=10
EnvironmentFile=$INSTALL_DIR/.env
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME" 2>/dev/null || true
  sudo systemctl restart "$SERVICE_NAME"
  BRIDGE_STARTED=true
  success "Servicio de sistema configurado"
fi

# Strategy 2: Systemd user service
if [ "$BRIDGE_STARTED" = false ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)" 2>/dev/null || true
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" 2>/dev/null || true

  if systemctl --user status 2>/dev/null | grep -q "State:" ; then
    info "Instalando servicio de usuario..."

    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/${SERVICE_NAME}.service" << SVCEOF
[Unit]
Description=TribuClaw Bridge
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$NODE_PATH $INSTALL_DIR/index.js
Restart=always
RestartSec=10
EnvironmentFile=$INSTALL_DIR/.env
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
SVCEOF

    loginctl enable-linger "$(whoami)" 2>/dev/null || true
    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user restart "$SERVICE_NAME"
    BRIDGE_STARTED=true
    success "Servicio de usuario configurado"
  fi
fi

# Strategy 3: Background process (fallback)
if [ "$BRIDGE_STARTED" = false ]; then
  warn "systemd no disponible. Iniciando en background..."

  pkill -f "node.*$INSTALL_DIR/index.js" 2>/dev/null || true
  sleep 1

  set -a
  . "$INSTALL_DIR/.env"
  set +a
  nohup "$NODE_PATH" "$INSTALL_DIR/index.js" >> "$INSTALL_DIR/bridge.log" 2>&1 &
  BRIDGE_PID=$!
  echo "$BRIDGE_PID" > "$INSTALL_DIR/bridge.pid"

  (crontab -l 2>/dev/null | grep -v "$SERVICE_NAME"; echo "@reboot cd $INSTALL_DIR && set -a && . .env && set +a && $NODE_PATH index.js >> bridge.log 2>&1 &  # $SERVICE_NAME") | crontab -

  BRIDGE_STARTED=true
  success "Bridge iniciado en background (PID: $BRIDGE_PID)"
fi

# ─────────────────────────────────────────────────
# Wait for bridge to be ready
# ─────────────────────────────────────────────────

info "Esperando que el Bridge esté listo..."
sleep 3

MAX_TRIES=10
TRIES=0
while [ $TRIES -lt $MAX_TRIES ]; do
  if curl -sf "http://localhost:${BRIDGE_PORT}/health" > /dev/null 2>&1; then
    success "Bridge responde en puerto $BRIDGE_PORT"
    break
  fi
  TRIES=$((TRIES+1))
  sleep 2
done

if [ $TRIES -eq $MAX_TRIES ]; then
  warn "El Bridge tardó en responder. Continuando..."
fi

# ─────────────────────────────────────────────────
# Callback to panel
# ─────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Conectando con TribuClaw..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CALLBACK_RESPONSE=$(curl -sf -X POST \
  "${PANEL_URL}/api/server/setup-callback" \
  -H "Content-Type: application/json" \
  -d "{\"setupToken\":\"${SETUP_TOKEN}\",\"bridgeToken\":\"${BRIDGE_TOKEN}\",\"port\":${BRIDGE_PORT}}" \
  2>&1)

CALLBACK_STATUS=$?

if [ $CALLBACK_STATUS -eq 0 ]; then
  success "¡Conectado con TribuClaw!"
else
  error "No se pudo conectar con el panel: $CALLBACK_RESPONSE"
  error ""
  error "El Bridge está corriendo. Comprueba tu conexión a internet e inténtalo de nuevo."
  error "Puedes reconectar manualmente desde: ${PANEL_URL}/import"
  exit 1
fi

# ─────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ✅  TribuClaw Bridge v2 instalado y conectado"
echo ""
echo "  Puerto:   $BRIDGE_PORT"
echo "  Panel:    $PANEL_URL"
echo "  Servicio: systemctl status $SERVICE_NAME"
echo ""
echo "  Vuelve al panel de TribuClaw — ya está todo listo."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
