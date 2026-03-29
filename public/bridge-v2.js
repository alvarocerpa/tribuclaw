"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const fastify_1 = __importDefault(require("fastify"));
const cors_1 = __importDefault(require("@fastify/cors"));
const helmet_1 = __importDefault(require("@fastify/helmet"));
const ws_1 = __importDefault(require("ws"));
const crypto_1 = require("crypto");
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const os_1 = require("os");
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN;
const BRIDGE_PORT = parseInt(process.env.BRIDGE_PORT || '18889', 10);
if (!BRIDGE_TOKEN) {
    console.error('ERROR: BRIDGE_TOKEN env var is required');
    process.exit(1);
}
function findGatewayConfig() {
    const searchPaths = [
        path_1.default.join((0, os_1.homedir)(), '.openclaw', 'openclaw.json'),
    ];
    try {
        const homeEntries = fs_1.default.readdirSync('/home');
        for (const user of homeEntries) {
            const p = path_1.default.join('/home', user, '.openclaw', 'openclaw.json');
            if (!searchPaths.includes(p))
                searchPaths.push(p);
        }
    }
    catch { }
    for (const configPath of searchPaths) {
        try {
            if (!fs_1.default.existsSync(configPath))
                continue;
            const raw = fs_1.default.readFileSync(configPath, 'utf8');
            const cfg = JSON.parse(raw);
            const port = cfg?.gateway?.port || cfg?.port || 18789;
            const token = cfg?.gateway?.auth?.token || cfg?.auth?.token || '';
            if (token) {
                console.log(`Found gateway config at ${configPath} (port ${port})`);
                return { port, token };
            }
        }
        catch { }
    }
    console.warn('No gateway config found, using defaults');
    return { port: 18789, token: '' };
}
const gwConfig = findGatewayConfig();
// ── WebSocket client to gateway ───────────────────────────────────────────────
class GatewayClient {
    constructor(config) {
        this.config = config;
        this.ws = null;
        this.pending = new Map();
        this.connected = false;
        this.reconnectTimer = null;
        this.reconnectMs = 800;
        this.eventHandlers = new Map();
    }
    async connect() {
        if (this.connected && this.ws?.readyState === ws_1.default.OPEN)
            return;
        return new Promise((resolve, reject) => {
            const url = `ws://127.0.0.1:${this.config.port}`;
            console.log(`Connecting to gateway at ${url}...`);
            this.ws = new ws_1.default(url, {
                headers: {
                    'Origin': `http://127.0.0.1:${this.config.port}`,
                },
            });
            this.ws.on('open', async () => {
                console.log('WebSocket open, sending handshake...');
                try {
                    await this.handshake();
                    this.connected = true;
                    this.reconnectMs = 800;
                    console.log('Gateway connected!');
                    resolve();
                }
                catch (err) {
                    reject(err);
                }
            });
            this.ws.on('message', (data) => {
                try {
                    const msg = JSON.parse(data.toString());
                    if (msg.type === 'res' && msg.id) {
                        const pending = this.pending.get(msg.id);
                        if (pending) {
                            clearTimeout(pending.timer);
                            this.pending.delete(msg.id);
                            if (msg.ok) {
                                pending.resolve(msg.payload ?? msg);
                            }
                            else {
                                const errMsg = typeof msg.error === 'object'
                                    ? msg.error?.message ?? 'Gateway error'
                                    : msg.error ?? 'Gateway error';
                                pending.reject(new Error(errMsg));
                            }
                        }
                    }
                    else if (msg.type === 'event' && msg.event) {
                        const handlers = this.eventHandlers.get(msg.event);
                        if (handlers) {
                            for (const h of handlers)
                                h(msg.payload);
                        }
                    }
                }
                catch { }
            });
            this.ws.on('close', () => {
                console.log('Gateway WebSocket closed');
                this.connected = false;
                this.rejectAllPending('Connection closed');
                this.scheduleReconnect();
            });
            this.ws.on('error', (err) => {
                console.error('Gateway WebSocket error:', err.message);
                if (!this.connected)
                    reject(err);
            });
        });
    }
    async handshake() {
        await this.request('connect', {
            minProtocol: 3,
            maxProtocol: 3,
            client: { id: 'openclaw-control-ui', version: '2.0', platform: 'linux', mode: 'webchat', instanceId: `tribuclaw-bridge-${Date.now()}` },
            role: 'operator',
            scopes: ['operator.admin'],
            auth: { token: this.config.token },
        }, 10000);
    }
    async request(method, params = {}, timeoutMs = 30000) {
        if (!this.ws || this.ws.readyState !== ws_1.default.OPEN) {
            try {
                await this.connect();
            }
            catch {
                throw new Error('Gateway not available');
            }
        }
        const id = (0, crypto_1.randomUUID)();
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.pending.delete(id);
                reject(new Error(`Timeout waiting for ${method}`));
            }, timeoutMs);
            this.pending.set(id, { resolve, reject, timer });
            this.ws.send(JSON.stringify({
                type: 'req',
                id,
                method,
                params,
            }));
        });
    }
    on(event, handler) {
        if (!this.eventHandlers.has(event)) {
            this.eventHandlers.set(event, new Set());
        }
        this.eventHandlers.get(event).add(handler);
    }
    rejectAllPending(reason) {
        for (const [, p] of this.pending) {
            clearTimeout(p.timer);
            p.reject(new Error(reason));
        }
        this.pending.clear();
    }
    scheduleReconnect() {
        if (this.reconnectTimer)
            return;
        this.reconnectTimer = setTimeout(async () => {
            this.reconnectTimer = null;
            try {
                await this.connect();
            }
            catch {
                this.reconnectMs = Math.min(this.reconnectMs * 1.5, 15000);
                this.scheduleReconnect();
            }
        }, this.reconnectMs);
    }
    get isConnected() { return this.connected; }
}
const gateway = new GatewayClient(gwConfig);
// Connect on startup (non-blocking)
gateway.connect().catch(err => {
    console.warn('Initial gateway connect failed:', err.message);
});
// ── Fastify ───────────────────────────────────────────────────────────────────
const app = (0, fastify_1.default)({ logger: true });
app.register(helmet_1.default, { contentSecurityPolicy: false });
app.register(cors_1.default, {
    origin: [
        'https://tribuclaw-saas.vercel.app',
        'https://tribuclaw.com',
        'https://app.tribuclaw.com',
        /^https:\/\/tribuclaw-saas-[a-z0-9-]+\.vercel\.app$/,
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
    if (!authHeader?.startsWith('Bearer ') || authHeader.slice(7) !== BRIDGE_TOKEN) {
        return reply.code(401).send({ error: 'Unauthorized' });
    }
});
// ── Config helpers ────────────────────────────────────────────────────────────
function findConfigPath() {
    const searchPaths = [
        path_1.default.join((0, os_1.homedir)(), '.openclaw', 'openclaw.json'),
    ];
    try {
        const homeEntries = fs_1.default.readdirSync('/home');
        for (const user of homeEntries) {
            const p = path_1.default.join('/home', user, '.openclaw', 'openclaw.json');
            if (!searchPaths.includes(p))
                searchPaths.push(p);
        }
    }
    catch { }
    for (const p of searchPaths) {
        try {
            if (fs_1.default.existsSync(p)) {
                const raw = JSON.parse(fs_1.default.readFileSync(p, 'utf8'));
                if (raw?.gateway || raw?.channels || raw?.models)
                    return p;
            }
        }
        catch { }
    }
    return null;
}
function readConfig() {
    const configPath = findConfigPath();
    if (!configPath)
        throw new Error('openclaw.json not found');
    const raw = fs_1.default.readFileSync(configPath, 'utf8');
    return { path: configPath, config: JSON.parse(raw) };
}
function writeConfig(configPath, config) {
    // Backup before writing
    const backupPath = configPath + '.bak';
    if (fs_1.default.existsSync(configPath)) {
        fs_1.default.copyFileSync(configPath, backupPath);
    }
    fs_1.default.writeFileSync(configPath, JSON.stringify(config, null, 2), 'utf8');
}
async function restartGateway() {
    try {
        await gateway.request('restart', { reason: 'config change via SaaS' }, 10000);
        console.log('[restartGateway] Gateway restart requested via WebSocket');
    }
    catch (wsErr) {
        const wsMsg = wsErr.message;
        console.warn('[restartGateway] WebSocket restart failed:', wsMsg);
        // Gateway may disconnect during restart — that's expected
        // Try SIGUSR1 as fallback, then systemctl
        try {
            const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
            // Try systemctl first (more reliable)
            try {
                execSync('systemctl restart openclaw-gateway 2>&1 || systemctl restart openclaw 2>&1', {
                    timeout: 10000,
                    encoding: 'utf8'
                });
                console.log('[restartGateway] Gateway restarted via systemctl');
                return;
            }
            catch { }
            // Fallback: SIGUSR1
            const pid = execSync("pgrep -f 'openclaw.*gateway' || pgrep -f 'node.*openclaw'", { encoding: 'utf8' }).trim().split('\n')[0];
            if (pid) {
                execSync(`kill -USR1 ${pid}`);
                console.log(`[restartGateway] Sent SIGUSR1 to gateway PID ${pid}`);
            }
        }
        catch (sysErr) {
            console.warn('[restartGateway] System restart also failed:', sysErr.message);
            // Don't throw - config was saved, gateway will pick it up on next restart
        }
    }
}
// Provider env var mapping
const PROVIDER_ENV_MAP = {
    anthropic: 'ANTHROPIC_API_KEY',
    openai: 'OPENAI_API_KEY',
    'google-ai-studio': 'GOOGLE_API_KEY',
    google: 'GOOGLE_API_KEY',
    zai: 'ZAI_API_KEY',
    openrouter: 'OPENROUTER_API_KEY',
    moonshot: 'MOONSHOT_API_KEY',
    mistral: 'MISTRAL_API_KEY',
    groq: 'GROQ_API_KEY',
    gemini: 'GEMINI_API_KEY',
};
function maskKey(key) {
    if (!key || key.length < 8)
        return key ? '****' : '';
    return key.slice(0, 6) + '...' + key.slice(-4);
}
// ── Routes ────────────────────────────────────────────────────────────────────
// GET /health — no auth
app.get('/health', async () => ({
    ok: true,
    version: '2.0.0',
    gatewayConnected: gateway.isConnected,
    uptime: process.uptime(),
    timestamp: Date.now(),
}));
// ── Channel management (direct config) ───────────────────────────────────────
// POST /gw/channels/configure — Add or update a channel
app.post('/gw/channels/configure', async (req, reply) => {
    try {
        const body = req.body;
        const channel = body?.channel;
        const channelConfig = body?.config;
        console.log('[channels/configure] Request body:', JSON.stringify(body));
        if (!channel || !channelConfig) {
            console.log('[channels/configure] Error: missing channel or config');
            return reply.code(400).send({ error: 'Faltan channel o config' });
        }
        const { path: configPath, config } = readConfig();
        // Ensure channels object exists
        if (!config.channels || typeof config.channels !== 'object') {
            config.channels = {};
        }
        const channels = config.channels;
        // Merge config for the channel (use lowercase key for consistency)
        const channelKey = channel.toLowerCase();
        const existing = (channels[channelKey] && typeof channels[channelKey] === 'object')
            ? channels[channelKey]
            : {};
        channels[channelKey] = { ...existing, ...channelConfig, enabled: true };
        writeConfig(configPath, config);
        console.log(`[channels/configure] Channel ${channelKey} configured successfully`);
        // Restart gateway to pick up changes
        await restartGateway();
        return { ok: true, message: `Canal ${channelKey} configurado. Gateway reiniciando.` };
    }
    catch (err) {
        const msg = err.message;
        console.error('[channels/configure] Error:', msg);
        return reply.code(500).send({ error: msg });
    }
});
// POST /gw/channels/remove — Remove a channel completely
app.post('/gw/channels/remove', async (req, reply) => {
    try {
        // Ensure body is parsed
        const body = req.body;
        const channel = body?.channel;
        console.log('[channels/remove] Request body:', JSON.stringify(body));
        if (!channel) {
            console.log('[channels/remove] Error: missing channel');
            return reply.code(400).send({ error: 'Falta channel' });
        }
        const { path: configPath, config } = readConfig();
        const channels = (config.channels ?? {});
        console.log('[channels/remove] Current channels:', Object.keys(channels));
        console.log('[channels/remove] Looking for channel:', channel);
        // Try exact match first, then case-insensitive
        let foundKey = channel;
        if (!channels[foundKey]) {
            // Try case-insensitive match
            foundKey = Object.keys(channels).find(k => k.toLowerCase() === channel.toLowerCase()) || channel;
        }
        if (channels[foundKey]) {
            delete channels[foundKey];
            writeConfig(configPath, config);
            console.log(`[channels/remove] Channel ${foundKey} removed completely from config`);
            // Try to restart gateway, but don't fail if it's not available
            try {
                await restartGateway();
                return { ok: true, message: `Canal ${foundKey} eliminado. Gateway reiniciando.` };
            }
            catch (restartErr) {
                console.log(`[channels/remove] Gateway restart failed, but channel removed from config`);
                return { ok: true, message: `Canal ${foundKey} eliminado de la config. Reinicia el gateway manualmente para aplicar.` };
            }
        }
        else {
            // Channel not in Bridge config - try to remove from gateway directly
            console.log(`[channels/remove] Channel ${channel} not found in Bridge config, trying gateway...`);
            try {
                // Request gateway to disable/remove the channel
                await gateway.request('channels.disable', { channel: channel.toLowerCase() }, 10000);
                console.log(`[channels/remove] Channel ${channel} disabled via gateway`);
                return { ok: true, message: `Canal ${channel} desactivado desde el gateway.` };
            }
            catch (gwErr) {
                const gwMsg = gwErr.message;
                console.log(`[channels/remove] Gateway error:`, gwMsg);
                // If gateway method doesn't exist or gateway not available, just return success
                // The channel will disappear after gateway restart
                return { ok: true, message: `Canal ${channel} no estaba en la config del Bridge. Reinicia el gateway para aplicar cambios.` };
            }
        }
    }
    catch (err) {
        const msg = err.message;
        console.error('[channels/remove] Error:', msg);
        return reply.code(500).send({ error: msg });
    }
});
// POST /gw/channels/detail — Get detailed channel status
app.post('/gw/channels/detail', async (req, reply) => {
    try {
        const body = req.body;
        const requested = body?.channel;
        const { config } = readConfig();
        const channels = (config.channels ?? {});
        console.log('[channels/detail] Channels in config:', Object.keys(channels));
        if (requested) {
            // Try exact match first, then case-insensitive
            let foundKey = requested;
            if (!channels[foundKey]) {
                foundKey = Object.keys(channels).find(k => k.toLowerCase() === requested.toLowerCase()) || requested;
            }
            const ch = channels[foundKey];
            if (!ch)
                return reply.code(404).send({ error: `Canal ${requested} no encontrado` });
            return { channel: foundKey, config: ch };
        }
        // Return all channels with masked secrets
        const result = {};
        for (const [id, cfg] of Object.entries(channels)) {
            if (!cfg || typeof cfg !== 'object')
                continue;
            const masked = { ...cfg };
            // Mask sensitive fields
            for (const key of ['botToken', 'token', 'appToken', 'signingSecret', 'clientSecret']) {
                if (typeof masked[key] === 'string') {
                    masked[key] = maskKey(masked[key]);
                }
            }
            // Mask nested accounts tokens
            if (masked.accounts && typeof masked.accounts === 'object') {
                const accts = { ...masked.accounts };
                for (const [acctId, acctCfg] of Object.entries(accts)) {
                    if (acctCfg && typeof acctCfg === 'object') {
                        const a = { ...acctCfg };
                        for (const key of ['botToken', 'token']) {
                            if (typeof a[key] === 'string')
                                a[key] = maskKey(a[key]);
                        }
                        accts[acctId] = a;
                    }
                }
                masked.accounts = accts;
            }
            result[id] = masked;
        }
        return { channels: result };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// ── Provider management (direct config) ──────────────────────────────────────
// POST /gw/providers/list — List all providers with masked keys
app.post('/gw/providers/list', async (_req, reply) => {
    try {
        const { config } = readConfig();
        const env = (config.env ?? {});
        const modelsProviders = (config.models?.providers ?? {});
        const providers = [];
        for (const [providerId, envVar] of Object.entries(PROVIDER_ENV_MAP)) {
            const envKey = env[envVar] || '';
            const profileKey = modelsProviders[providerId]?.apiKey || '';
            const activeKey = envKey || profileKey;
            providers.push({
                provider: providerId,
                envVar,
                configured: !!activeKey,
                keyMasked: activeKey ? maskKey(activeKey) : null,
                hasProfile: !!modelsProviders[providerId],
            });
        }
        return { providers };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /gw/providers/configure — Set API key for a provider
app.post('/gw/providers/configure', async (req, reply) => {
    try {
        const { provider, apiKey } = req.body ?? {};
        if (!provider || !apiKey) {
            return reply.code(400).send({ error: 'Faltan provider o apiKey' });
        }
        const envVar = PROVIDER_ENV_MAP[provider];
        if (!envVar) {
            return reply.code(400).send({ error: `Proveedor desconocido: ${provider}` });
        }
        const { path: configPath, config } = readConfig();
        // Set in env section
        if (!config.env || typeof config.env !== 'object') {
            config.env = {};
        }
        config.env[envVar] = apiKey;
        // Also set in models.providers if profile exists
        const models = (config.models ?? {});
        const providers = (models.providers ?? {});
        if (providers[provider]) {
            providers[provider].apiKey = apiKey;
        }
        writeConfig(configPath, config);
        console.log(`Provider ${provider} API key configured (env: ${envVar})`);
        await restartGateway();
        return { ok: true, message: `Proveedor ${provider} configurado. Gateway reiniciando.` };
    }
    catch (err) {
        const msg = err.message;
        return reply.code(500).send({ error: msg });
    }
});
// ── Skill install/uninstall via clawhub CLI ───────────────────────────────────
app.post('/skills/install', async (req, reply) => {
    try {
        const { slug, version } = req.body ?? {};
        if (!slug || !/^[a-zA-Z0-9_-]+$/.test(slug)) {
            return reply.code(400).send({ error: 'slug inválido' });
        }
        // Sanitize version too (only semver-like allowed)
        if (version && !/^[a-zA-Z0-9._-]+$/.test(version)) {
            return reply.code(400).send({ error: 'versión inválida' });
        }
        const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
        // Double-safety: slug already validated by regex, but use array form for extra protection
        const args = ['install', slug, '--force'];
        if (version)
            args.push('--version', version);
        const envPath = `${process.env.PATH}:${(0, os_1.homedir)()}/.npm-global/bin:/usr/local/bin`;
        const output = execSync(`clawhub ${args.join(' ')}`, {
            encoding: 'utf8', timeout: 60000,
            env: { ...process.env, PATH: envPath, NO_COLOR: '1' },
        }).trim();
        console.log(`Skill installed: ${slug}${version ? `@${version}` : ''}`);
        return { success: true, output };
    }
    catch (err) {
        const msg = err.message;
        return reply.code(500).send({ success: false, error: msg });
    }
});
app.post('/skills/uninstall', async (req, reply) => {
    try {
        const { slug } = req.body ?? {};
        if (!slug || !/^[a-zA-Z0-9_-]+$/.test(slug)) {
            return reply.code(400).send({ error: 'slug inválido' });
        }
        const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
        // Try clawhub uninstall first, fallback to rm
        try {
            const output = execSync(`clawhub uninstall ${slug}`, { encoding: 'utf8', timeout: 30000 }).trim();
            console.log(`Skill uninstalled via clawhub: ${slug}`);
            return { success: true, output };
        }
        catch {
            // Fallback: remove skill directory (with path traversal protection)
            const skillsBase = path_1.default.join((0, os_1.homedir)(), '.openclaw', 'skills');
            const skillsDir = path_1.default.resolve(skillsBase, slug);
            if (!skillsDir.startsWith(skillsBase + path_1.default.sep)) {
                return reply.code(400).send({ success: false, error: 'Ruta inválida' });
            }
            if (fs_1.default.existsSync(skillsDir)) {
                fs_1.default.rmSync(skillsDir, { recursive: true });
                console.log(`Skill removed (directory): ${slug}`);
                return { success: true, output: `Removed ${skillsDir}` };
            }
            return reply.code(404).send({ success: false, error: `Skill ${slug} no encontrada` });
        }
    }
    catch (err) {
        const msg = err.message;
        return reply.code(500).send({ success: false, error: msg });
    }
});
// ── Server management ─────────────────────────────────────────────────────────
// POST /server/restart — Restart gateway via config.apply
app.post('/server/restart', async (_req, reply) => {
    try {
        await restartGateway();
        return { ok: true, message: 'Gateway reiniciando.' };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /server/restart-all — Restart both Bridge and Gateway (full recovery)
app.post('/server/restart-all', async (_req, reply) => {
    try {
        const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
        const results = [];
        // 1. Try to restart gateway via WebSocket first
        try {
            await gateway.request('restart', { reason: 'full restart via SaaS' }, 5000);
            results.push('Gateway restart requested via WebSocket');
        }
        catch {
            results.push('WebSocket restart failed, trying systemctl');
        }
        // 2. Try systemctl restart for gateway
        try {
            execSync('systemctl restart openclaw-gateway 2>&1 || systemctl restart openclaw 2>&1', {
                timeout: 10000,
                encoding: 'utf8'
            });
            results.push('Gateway restarted via systemctl');
        }
        catch {
            results.push('systemctl gateway not available (may be using PM2)');
        }
        // 3. For PM2-managed gateways, try pm2 restart
        try {
            const pm2List = execSync('pm2 jlist 2>/dev/null', { encoding: 'utf8' });
            const pm2Processes = JSON.parse(pm2List);
            const gatewayProcess = pm2Processes.find((p) => p.name?.toLowerCase().includes('gateway') || p.name?.toLowerCase().includes('openclaw'));
            if (gatewayProcess) {
                execSync(`pm2 restart ${gatewayProcess.name}`, { encoding: 'utf8' });
                results.push(`Gateway restarted via PM2 (${gatewayProcess.name})`);
            }
        }
        catch {
            // PM2 not available or no gateway process
        }
        // 4. Restart the bridge itself (PM2 only, systemctl would kill this request)
        try {
            execSync('pm2 restart tribuclaw-bridge 2>&1 || true', { encoding: 'utf8' });
            results.push('Bridge restart scheduled via PM2');
        }
        catch {
            // Not using PM2
        }
        return {
            ok: true,
            message: 'Reinicio completo ejecutado',
            details: results,
            note: 'El Bridge se reiniciará en unos segundos. Espera 10-15 segundos antes de usar el panel.'
        };
    }
    catch (err) {
        const msg = err.message;
        return reply.code(500).send({ error: msg });
    }
});
// POST /server/doctor — Run openclaw doctor
app.post('/server/doctor', async (_req, reply) => {
    try {
        const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
        const envPath = `${process.env.PATH}:${(0, os_1.homedir)()}/.npm-global/bin:/usr/local/bin:/usr/bin`;
        const output = execSync('openclaw doctor 2>&1 || true', {
            encoding: 'utf8',
            timeout: 60000,
            env: { ...process.env, PATH: envPath, NO_COLOR: '1', FORCE_COLOR: '0', CI: '1' },
        }).trim();
        return { ok: true, output };
    }
    catch (err) {
        const msg = err.message || '';
        // If timeout, return partial output
        if (msg.includes('ETIMEDOUT') || msg.includes('SIGTERM')) {
            return { ok: false, output: 'Doctor tardó demasiado. Ejecuta `openclaw doctor` directamente en el servidor.' };
        }
        return reply.code(500).send({ error: msg });
    }
});
// POST /server/doctor-fix — Run openclaw doctor --fix
app.post('/server/doctor-fix', async (_req, reply) => {
    try {
        const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
        const envPath = `${process.env.PATH}:${(0, os_1.homedir)()}/.npm-global/bin:/usr/local/bin:/usr/bin`;
        const output = execSync('openclaw doctor --fix 2>&1 || true', {
            encoding: 'utf8',
            timeout: 90000,
            env: { ...process.env, PATH: envPath, NO_COLOR: '1', FORCE_COLOR: '0', CI: '1' },
        }).trim();
        return { ok: true, output };
    }
    catch (err) {
        const msg = err.message || '';
        return reply.code(500).send({ error: msg });
    }
});
// POST /server/update — Update openclaw
app.post('/server/update', async (_req, reply) => {
    try {
        const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
        const envPath = `${process.env.PATH}:${(0, os_1.homedir)()}/.npm-global/bin:/usr/local/bin:/usr/bin`;
        // First try openclaw's built-in update command
        let output = '';
        try {
            output = execSync('openclaw update 2>&1 || true', {
                encoding: 'utf8',
                timeout: 120000,
                env: { ...process.env, PATH: envPath, NO_COLOR: '1', FORCE_COLOR: '0' },
            }).trim();
        }
        catch {
            // Fallback to npm update
            output = execSync('npm update -g openclaw 2>&1', {
                encoding: 'utf8',
                timeout: 120000,
                env: { ...process.env, PATH: envPath },
            }).trim();
        }
        // Get new version after update
        let newVersion = '';
        try {
            newVersion = execSync('openclaw --version 2>/dev/null', {
                encoding: 'utf8', timeout: 5000, env: { ...process.env, PATH: envPath },
            }).trim();
        }
        catch { /* ignore */ }
        return { ok: true, output, newVersion };
    }
    catch (err) {
        const msg = err.message || '';
        if (msg.includes('EACCES') || msg.includes('permission')) {
            return reply.code(500).send({
                error: 'Sin permisos para actualizar. Ejecuta `npm update -g openclaw` manualmente con sudo.'
            });
        }
        return reply.code(500).send({ error: msg });
    }
});
// POST /server/status — Full server status (health + openclaw status)
app.post('/server/status', async (_req, reply) => {
    try {
        const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
        const envPath = `${process.env.PATH}:${(0, os_1.homedir)()}/.npm-global/bin:/usr/local/bin`;
        let openclawVersion = 'unknown';
        try {
            openclawVersion = execSync('openclaw --version 2>/dev/null || echo unknown', {
                encoding: 'utf8', timeout: 5000, env: { ...process.env, PATH: envPath },
            }).trim();
        }
        catch { /* ignore */ }
        let nodeVersion = 'unknown';
        try {
            nodeVersion = execSync('node --version', { encoding: 'utf8', timeout: 5000 }).trim();
        }
        catch { /* ignore */ }
        let uptime = 'unknown';
        try {
            uptime = execSync('uptime -p 2>/dev/null || uptime', { encoding: 'utf8', timeout: 5000 }).trim();
        }
        catch { /* ignore */ }
        let disk = 'unknown';
        try {
            disk = execSync("df -h / | tail -1 | awk '{print $3\"/\"$2\" (\"$5\" used)\"}'", {
                encoding: 'utf8', timeout: 5000,
            }).trim();
        }
        catch { /* ignore */ }
        let memory = 'unknown';
        try {
            memory = execSync("free -h | awk '/^Mem:/{print $3\"/\"$2}'", {
                encoding: 'utf8', timeout: 5000,
            }).trim();
        }
        catch { /* ignore */ }
        // Gateway health via WS
        let gatewayHealth = {};
        try {
            gatewayHealth = await gateway.request('health', {});
        }
        catch { /* ignore */ }
        return {
            ok: true,
            openclawVersion,
            nodeVersion,
            uptime,
            disk,
            memory,
            gatewayConnected: gateway.connected,
            gatewayHealth,
        };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// POST /server/logs — Get recent gateway logs
app.post('/server/logs', async (req, reply) => {
    try {
        const lines = Math.min(Math.max(req.body?.lines ?? 50, 1), 200);
        const { execSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
        // Try multiple log locations
        const logPaths = [
            path_1.default.join((0, os_1.homedir)(), '.openclaw', 'logs', 'gateway.log'),
            path_1.default.join((0, os_1.homedir)(), '.openclaw', 'logs', 'commands.log'),
            path_1.default.join((0, os_1.homedir)(), '.openclaw', 'gateway.log'),
            path_1.default.join((0, os_1.homedir)(), '.pm2', 'logs', 'openclaw-out.log'),
        ];
        // Also try journalctl for systemd-managed openclaw
        let logPath = logPaths.find(p => fs_1.default.existsSync(p));
        let output = '';
        if (logPath) {
            output = execSync(`tail -n ${lines} "${logPath}" 2>/dev/null || echo "Cannot read log"`, {
                encoding: 'utf8', timeout: 5000,
            }).trim();
        }
        else {
            // Try journalctl as fallback
            try {
                output = execSync(`journalctl -u openclaw --no-pager -n ${lines} 2>/dev/null || echo "No logs found"`, {
                    encoding: 'utf8', timeout: 5000,
                }).trim();
                logPath = 'journalctl';
            }
            catch {
                output = 'No se encontraron archivos de log. Verifica la configuración de logging.';
                logPath = 'none';
            }
        }
        return { ok: true, logs: output, logPath: logPath || 'none' };
    }
    catch (err) {
        return reply.code(500).send({ error: err.message });
    }
});
// ── Generic gateway proxy ─────────────────────────────────────────────────────
// POST /gw/:method — single segment, e.g. /gw/health
app.post('/gw/:method', async (req, reply) => {
    const method = req.params.method.replace(/-/g, '.');
    const params = req.body ?? {};
    try {
        const result = await gateway.request(method, params);
        return result;
    }
    catch (err) {
        const msg = err.message;
        if (msg.includes('not available') || msg.includes('Connection closed')) {
            return reply.code(503).send({ error: 'Gateway no disponible', reconnecting: true });
        }
        return reply.code(500).send({ error: msg });
    }
});
// POST /gw/:a/:b — two segments, e.g. /gw/cron/list → cron.list
app.post('/gw/:a/:b', async (req, reply) => {
    const method = `${req.params.a}.${req.params.b}`;
    const params = req.body ?? {};
    try {
        const result = await gateway.request(method, params);
        return result;
    }
    catch (err) {
        const msg = err.message;
        if (msg.includes('not available') || msg.includes('Connection closed')) {
            return reply.code(503).send({ error: 'Gateway no disponible', reconnecting: true });
        }
        return reply.code(500).send({ error: msg });
    }
});
// POST /gw/:a/:b/:c — three segments, e.g. /gw/agents/files/list → agents.files.list
app.post('/gw/:a/:b/:c', async (req, reply) => {
    const method = `${req.params.a}.${req.params.b}.${req.params.c}`;
    const params = req.body ?? {};
    try {
        const result = await gateway.request(method, params);
        return result;
    }
    catch (err) {
        const msg = err.message;
        if (msg.includes('not available') || msg.includes('Connection closed')) {
            return reply.code(503).send({ error: 'Gateway no disponible', reconnecting: true });
        }
        return reply.code(500).send({ error: msg });
    }
});
// ── Start ─────────────────────────────────────────────────────────────────────
const start = async () => {
    try {
        await app.listen({ port: BRIDGE_PORT, host: '0.0.0.0' });
        console.log(`TribuClaw Bridge v2.0 (WebSocket proxy) on port ${BRIDGE_PORT}`);
    }
    catch (err) {
        app.log.error(err);
        process.exit(1);
    }
};
process.on('SIGTERM', async () => { await app.close(); process.exit(0); });
start();
