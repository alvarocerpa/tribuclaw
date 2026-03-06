#!/bin/bash
# TribuClaw Bridge Installer
# Usage: curl -fsSL https://tribuclaw.com/install-bridge.sh | bash -s -- <setupToken> --user <username> [--full]
# 
# --full: installs OpenClaw + Cortex + Bridge (for new servers)
# --user: target user to install under (runs as that user)
# (no flag): installs only Bridge (for existing OpenClaw installations)

set -e

SETUP_TOKEN="$1"
FULL_INSTALL=false
TARGET_USER=""

# Parse arguments
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --full) FULL_INSTALL=true ;;
    --user) shift; TARGET_USER="$1" ;;
  esac
  shift 2>/dev/null || true
done

PANEL_URL="https://tribuclaw-saas.vercel.app"
BRIDGE_PORT=18888

# ─────────────────────────────────────────────────
# If running as root with --user, re-exec as target user
# ─────────────────────────────────────────────────

if [ "$(id -u)" = "0" ] && [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
  # Ensure target user exists — create automatically for --full installs
  if ! id "$TARGET_USER" &>/dev/null; then
    if [ "$FULL_INSTALL" = true ]; then
      echo -e "\033[0;34m[INFO]\033[0m  Creando usuario '$TARGET_USER'..."
      useradd -m -s /bin/bash "$TARGET_USER"
      echo -e "\033[0;32m[OK]\033[0m    Usuario '$TARGET_USER' creado"
    else
      echo -e "\033[0;31m[ERROR]\033[0m El usuario '$TARGET_USER' no existe en este servidor."
      echo -e "\033[0;31m[ERROR]\033[0m Créalo primero o usa un usuario existente."
      exit 1
    fi
  fi

  echo -e "\033[0;34m[INFO]\033[0m  Ejecutando como root. Instalando bajo el usuario '$TARGET_USER'..."

  # Open bridge port in firewall (if UFW is active)
  if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow ${BRIDGE_PORT:-18888}/tcp >/dev/null 2>&1 && \
      echo -e "\033[0;32m[OK]\033[0m    Puerto ${BRIDGE_PORT:-18888} abierto en el firewall" || true
  fi
  
  # Enable linger for systemd user services
  loginctl enable-linger "$TARGET_USER" 2>/dev/null || true
  
  # Get target user's home directory
  TARGET_HOME=$(eval echo "~$TARGET_USER")
  INSTALL_DIR="$TARGET_HOME/tribuclaw-bridge"
  
  # Run the installation steps as the target user where needed,
  # but use root for systemd system service (avoids D-Bus issues)
  # Download script and run as target user with sudo
  SCRIPT_URL="https://tribuclaw.com/install-bridge.sh"
  FULL_FLAG=""
  [ "$FULL_INSTALL" = true ] && FULL_FLAG=" --full"
  
  # Use sudo -u which preserves better env than su -
  sudo -u "$TARGET_USER" -i bash -c "curl -fsSL $SCRIPT_URL | bash -s -- $SETUP_TOKEN --user $TARGET_USER$FULL_FLAG"
  exit $?
fi

# If --user was passed but we're already that user (from the re-exec), continue normally
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
echo "  Bridge Installer"
if [ "$FULL_INSTALL" = true ]; then
  echo "  Mode: FULL (OpenClaw + Cortex + Bridge)"
else
  echo "  Mode: Bridge only"
fi
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
    error "Node.js no está instalado. Instala Node.js 18+ primero:"
    error "  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -"
    error "  apt-get install -y nodejs"
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

  # Ensure npm global bin is in PATH
  export PATH="$HOME/.npm-global/bin:$PATH"
  npm config set prefix "$HOME/.npm-global" 2>/dev/null || true

  # Check if openclaw is installed for THIS user (npm global prefix)
  OPENCLAW_BIN="$HOME/.npm-global/bin/openclaw"
  if [ -x "$OPENCLAW_BIN" ]; then
    warn "OpenClaw ya está instalado para este usuario: $($OPENCLAW_BIN --version 2>/dev/null || echo 'versión desconocida')"
  else
    info "Instalando OpenClaw para el usuario $(whoami)..."
    npm install -g openclaw 2>&1 | tail -5
    success "OpenClaw instalado"
  fi
fi

# ─────────────────────────────────────────────────
# Install Bridge
# ─────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Instalando TribuClaw Bridge en $INSTALL_DIR..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p "$INSTALL_DIR"

# Write package.json
cat > "$INSTALL_DIR/package.json" << 'PKGJSON'
{
  "name": "tribuclaw-bridge",
  "version": "1.0.0",
  "description": "TribuClaw Bridge Server",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": {
    "fastify": "^4.28.1",
    "@fastify/cors": "^9.0.1",
    "@fastify/helmet": "^11.1.1",
    "dotenv": "^16.4.5"
  }
}
PKGJSON

# Write Bridge JS inline
cat > "$INSTALL_DIR/index.js" << 'BRIDGE_JS_END'
"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const fastify_1 = __importDefault(require("fastify"));
const cors_1 = __importDefault(require("@fastify/cors"));
const helmet_1 = __importDefault(require("@fastify/helmet"));
const child_process_1 = require("child_process");
const util_1 = require("util");
const os_1 = require("os");
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const execAsync = (0, util_1.promisify)(child_process_1.exec);
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN;
const BRIDGE_PORT = parseInt(process.env.BRIDGE_PORT || '18800', 10);
const VERSION = '1.0.0';
if (!BRIDGE_TOKEN) {
    console.error('ERROR: BRIDGE_TOKEN env var is required');
    process.exit(1);
}
// ── Shell helper ──────────────────────────────────────────────────────────────
async function run(cmd, timeoutMs = 30000) {
    return execAsync(cmd, {
        timeout: timeoutMs,
        env: {
            ...process.env,
            PATH: '/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/root/.npm-global/bin:/home/claw1/.npm-global/bin',
        },
    });
}
// SECURITY: Validates that a param only contains safe chars before shell interpolation
const SAFE_PARAM_RE = /^[a-zA-Z0-9_:.-]{1,128}$/;
function assertSafeParam(value, name) {
    if (!SAFE_PARAM_RE.test(value)) {
        throw new Error(`Invalid ${name}: contains unsafe characters`);
    }
}
function parseJson(raw, fallback) {
    const trimmed = raw.trim();
    if (!trimmed)
        return fallback;
    try {
        if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
            return JSON.parse(trimmed);
        }
        // JSONL
        const lines = trimmed.split('\n').filter(l => l.trim().startsWith('{') || l.trim().startsWith('['));
        if (lines.length === 1)
            return JSON.parse(lines[0]);
        if (lines.length > 1)
            return lines.map(l => { try {
                return JSON.parse(l);
            }
            catch {
                return null;
            } }).filter(Boolean);
        return fallback;
    }
    catch {
        return fallback;
    }
}
// ── Fastify setup ─────────────────────────────────────────────────────────────
const app = (0, fastify_1.default)({ logger: true });
app.register(helmet_1.default, { contentSecurityPolicy: false });
app.register(cors_1.default, {
    origin: [
        'https://tribuclaw-saas.vercel.app',
        'https://tribuclaw.com',
        /^https:\/\/tribuclaw-saas-[a-z0-9-]+\.vercel\.app$/,
        'http://localhost:3000',
        'http://localhost:3001',
    ],
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    credentials: true,
});
// ── Auth hook ─────────────────────────────────────────────────────────────────
app.addHook('onRequest', async (request, reply) => {
    if (request.url === '/health' || request.method === 'OPTIONS')
        return;
    const authHeader = request.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return reply.code(401).send({ error: 'Missing authorization header' });
    }
    const token = authHeader.slice(7);
    if (token !== BRIDGE_TOKEN) {
        return reply.code(401).send({ error: 'Invalid token' });
    }
});
// ── Routes ────────────────────────────────────────────────────────────────────
// GET /health — no auth
app.get('/health', async () => {
    return { ok: true, version: VERSION, uptime: process.uptime(), timestamp: Date.now() };
});
// GET /agents
app.get('/agents', async (_req, reply) => {
    try {
        const { stdout } = await run("openclaw agents list --json 2>/dev/null || echo '[]'");
        return parseJson(stdout, []);
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// GET /agents/:id/crons
app.get('/agents/:id/crons', async (req, reply) => {
    const { id } = req.params;
    try {
        assertSafeParam(id, 'id');
        const { stdout } = await run("openclaw cron list --json 2>/dev/null || echo '{\"jobs\":[]}'");
        const parsed = parseJson(stdout, { jobs: [] });
        const all = Array.isArray(parsed) ? parsed : (parsed.jobs ?? []);
        const filtered = all.filter(c => c.agentId === id ||
            (typeof c.sessionKey === 'string' && c.sessionKey.startsWith(`agent:${id}`)));
        return { crons: filtered };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /agents/:id/crons/sync
app.post('/agents/:id/crons/sync', async (req, reply) => {
    try {
        assertSafeParam(req.params.id, 'id');
        const { stdout } = await run("openclaw cron list --json 2>/dev/null || echo '{\"jobs\":[]}'");
        const parsed = parseJson(stdout, { jobs: [] });
        const crons = Array.isArray(parsed) ? parsed : (parsed.jobs ?? []);
        return { synced: true, crons };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /agents/:id/crons/:cronId/toggle
app.post('/agents/:id/crons/:cronId/toggle', async (req, reply) => {
    const { id, cronId } = req.params;
    const { enabled } = req.body || {};
    try {
        assertSafeParam(id, 'id');
        assertSafeParam(cronId, 'cronId');
        const verb = enabled ? 'enable' : 'disable';
        await run(`openclaw cron ${verb} ${cronId} 2>/dev/null`);
        return { ok: true };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /agents/:id/crons/:cronId/run
app.post('/agents/:id/crons/:cronId/run', async (req, reply) => {
    const { id, cronId } = req.params;
    try {
        assertSafeParam(id, 'id');
        assertSafeParam(cronId, 'cronId');
        await run(`openclaw cron run ${cronId} 2>/dev/null`, 60000);
        return { ok: true };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// GET /agents/:id/crons/:cronId/runs
app.get('/agents/:id/crons/:cronId/runs', async (req, reply) => {
    const { id, cronId } = req.params;
    try {
        assertSafeParam(id, 'id');
        assertSafeParam(cronId, 'cronId');
        const { stdout } = await run(`openclaw cron runs ${cronId} --json 2>/dev/null || echo '[]'`);
        return { runs: parseJson(stdout, []) };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// GET /agents/:id/files
app.get('/agents/:id/files', async (req, reply) => {
    const { id } = req.params;
    try {
        assertSafeParam(id, 'id');
    }
    catch {
        return reply.code(400).send({ error: 'Invalid agent id' });
    }
    const wsDir = path_1.default.join((0, os_1.homedir)(), `.openclaw/workspace-${id}`);
    try {
        if (!fs_1.default.existsSync(wsDir))
            return { files: [] };
        const files = fs_1.default.readdirSync(wsDir)
            .filter(f => f.endsWith('.md'));
        return { files };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
const FILENAME_RE = /^[a-zA-Z0-9_-]+\.md$/;
// PUT /agents/:id/files
app.put('/agents/:id/files', async (req, reply) => {
    const { id } = req.params;
    try {
        assertSafeParam(id, 'id');
    }
    catch {
        return reply.code(400).send({ error: 'Invalid agent id' });
    }
    const { filename, content } = req.body || {};
    if (!filename || !FILENAME_RE.test(filename)) {
        return reply.code(400).send({ error: 'Invalid filename' });
    }
    if (content === undefined) {
        return reply.code(400).send({ error: 'Missing content' });
    }
    const wsDir = path_1.default.join((0, os_1.homedir)(), `.openclaw/workspace-${id}`);
    try {
        fs_1.default.mkdirSync(wsDir, { recursive: true });
        fs_1.default.writeFileSync(path_1.default.join(wsDir, filename), content, 'utf8');
        return { ok: true };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// GET /agents/:id/metrics
app.get('/agents/:id/metrics', async (req, reply) => {
    const { id } = req.params;
    try {
        assertSafeParam(id, 'id');
        const { stdout } = await run("openclaw agents list --json 2>/dev/null || echo '[]'");
        const agents = parseJson(stdout, []);
        const agent = agents.find(a => a.id === id || a.name === id);
        return {
            agentId: id,
            status: agent ? (agent.status || 'unknown') : 'not_found',
            uptime: process.uptime(),
            timestamp: Date.now(),
        };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// GET /skills
app.get('/skills', async (_req, reply) => {
    try {
        const { stdout } = await run("openclaw skills list --json 2>/dev/null || echo '[]'");
        return parseJson(stdout, []);
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /agents/:id/start
app.post('/agents/:id/start', async (req, reply) => {
    const { id } = req.params;
    try {
        assertSafeParam(id, 'id');
        await run(`openclaw agent start ${id} 2>/dev/null`);
        return { ok: true };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /agents/:id/stop
app.post('/agents/:id/stop', async (req, reply) => {
    const { id } = req.params;
    try {
        assertSafeParam(id, 'id');
        await run(`openclaw agent stop ${id} 2>/dev/null`);
        return { ok: true };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /agents/:id/restart
app.post('/agents/:id/restart', async (req, reply) => {
    const { id } = req.params;
    try {
        assertSafeParam(id, 'id');
        await run(`openclaw agent restart ${id} 2>/dev/null`);
        return { ok: true };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// GET /system/status
app.get('/system/status', async (_req, reply) => {
    try {
        const { stdout } = await run("openclaw gateway status --json 2>/dev/null || echo '{}'");
        return parseJson(stdout, {});
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /system/update
app.post('/system/update', async (_req, reply) => {
    try {
        const { stdout, stderr } = await run('npm update -g openclaw 2>&1', 120000);
        return { ok: true, output: stdout + stderr };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// ── Start ─────────────────────────────────────────────────────────────────────
const start = async () => {
    try {
        await app.listen({ port: BRIDGE_PORT, host: '0.0.0.0' });
        console.log(`TribuClaw Bridge running on port ${BRIDGE_PORT}`);
    }
    catch (err) {
        app.log.error(err);
        process.exit(1);
    }
};
process.on('SIGTERM', async () => {
    await app.close();
    process.exit(0);
});
start();
BRIDGE_JS_END

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
ENVEOF
chmod 600 "$INSTALL_DIR/.env"
success "Token generado"

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

# Strategy 2: Systemd user service (if D-Bus session available)
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
  
  # Kill any existing instance
  pkill -f "node.*$INSTALL_DIR/index.js" 2>/dev/null || true
  sleep 1
  
  # Source env and start
  set -a
  . "$INSTALL_DIR/.env"
  set +a
  nohup "$NODE_PATH" "$INSTALL_DIR/index.js" >> "$INSTALL_DIR/bridge.log" 2>&1 &
  BRIDGE_PID=$!
  
  # Write PID file for management
  echo "$BRIDGE_PID" > "$INSTALL_DIR/bridge.pid"
  
  # Create a crontab entry to auto-start on reboot
  (crontab -l 2>/dev/null | grep -v "$SERVICE_NAME"; echo "@reboot cd $INSTALL_DIR && set -a && . .env && set +a && $NODE_PATH index.js >> bridge.log 2>&1 &  # $SERVICE_NAME") | crontab -
  
  BRIDGE_STARTED=true
  success "Bridge iniciado en background (PID: $BRIDGE_PID)"
fi

# ─────────────────────────────────────────────────
# Wait for bridge to be ready
# ─────────────────────────────────────────────────

info "Esperando que el Bridge esté listo..."
sleep 3

# Verify locally
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
  warn "El Bridge tardó en responder. Continuando de todas formas..."
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
  exit 1
fi

# ─────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ✅  TribuClaw Bridge instalado y conectado"
echo ""
echo "  Puerto: $BRIDGE_PORT"
echo "  Servicio: systemctl --user status $SERVICE_NAME"
echo ""
echo "  Vuelve al panel de TribuClaw — ya está todo listo."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
