#!/usr/bin/env python3
"""
trend-digest.py — Digest diario de trends IA para TribuClaw
Ejecutar: una vez al día (cron 15 8 * * *)

Monitorea fuentes clave, agrupa todo y manda UN solo mensaje a Álvaro
con los 3-5 trends más relevantes del día + oportunidad de post.
"""

import json, re, time, hashlib, urllib.request, os
from datetime import datetime, timezone, timedelta
from pathlib import Path
import xml.etree.ElementTree as ET

# ── Load .env ──────────────────────────────────────────────────────────────
_env_path = Path.home() / ".openclaw" / ".env"
if _env_path.exists():
    for _line in _env_path.read_text().splitlines():
        _line = _line.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _k, _, _v = _line.partition("=")
            os.environ.setdefault(_k.strip(), _v.strip())

# ── Config ─────────────────────────────────────────────────────────────────
KIMO_BOT_TOKEN = os.environ.get("KIMO_BOT_TOKEN", "")
KIMO_CHAT_ID   = os.environ.get("KIMO_CHAT_ID", "")
SEEN_FILE      = Path("/tmp/trend-seen.json")
LOG_FILE       = Path("/tmp/trend-alerts.log")

# ── Fuentes ────────────────────────────────────────────────────────────────
SOURCES = [
    {
        "name": "OpenClaw Release",
        "url": "https://github.com/openclaw/openclaw/releases.atom",
        "priority": 10,   # máxima prioridad — siempre publicar
        "keywords": []
    },
    {
        "name": "HN · OpenClaw",
        "url": "https://hnrss.org/newest?q=openclaw&points=10",
        "priority": 9,
        "keywords": []
    },
    {
        "name": "HN · Anthropic/Claude",
        "url": "https://hnrss.org/newest?q=claude+anthropic&points=15",
        "priority": 7,
        "keywords": ["claude", "anthropic", "model", "api", "release", "agent"]
    },
    {
        "name": "HN · OpenAI",
        "url": "https://hnrss.org/newest?q=openai&points=15",
        "priority": 7,
        "keywords": ["gpt", "openai", "model", "agent", "api", "release"]
    },
    {
        "name": "HN · Agentes IA",
        "url": "https://hnrss.org/newest?q=ai+agent&points=30",
        "priority": 6,
        "keywords": ["agent", "autonomous", "llm", "openclaw", "workflow"]
    },
    {
        "name": "TechCrunch AI",
        "url": "https://techcrunch.com/category/artificial-intelligence/feed/",
        "priority": 5,
        "keywords": ["anthropic", "openai", "agent", "claude", "llm", "release"]
    },
    {
        "name": "Reddit · r/artificial",
        "url": "https://old.reddit.com/r/artificial/top/.rss?t=day&limit=10",
        "priority": 4,
        "keywords": ["agent", "openclaw", "claude", "anthropic", "openai", "llm", "release"]
    },
    # Google Alerts (añadir más URLs aquí cuando Álvaro cree más alertas)
    {
        "name": "Google Alert · OpenClaw",
        "url": "https://www.google.com/alerts/feeds/11694749136647075663/2169383205889071736",
        "priority": 9,
        "keywords": []
    },
]

# ── Helpers ─────────────────────────────────────────────────────────────────
def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    print(f"{ts} — {msg}")
    with open(LOG_FILE, "a") as f:
        f.write(f"{ts} — {msg}\n")

def load_seen():
    if SEEN_FILE.exists():
        try: return json.loads(SEEN_FILE.read_text())
        except: pass
    return {}

def save_seen(seen):
    SEEN_FILE.write_text(json.dumps(seen, indent=2))

def item_id(url):
    return hashlib.md5(url.encode()).hexdigest()[:10]

def is_relevant(text, keywords):
    if not keywords: return True
    tl = text.lower()
    return any(k.lower() in tl for k in keywords)

def fetch_feed(url):
    h = {"User-Agent": "Mozilla/5.0 (compatible; TribuClawBot/1.0)"}
    try:
        req = urllib.request.Request(url, headers=h)
        with urllib.request.urlopen(req, timeout=10) as r:
            if r.status == 200: return r.read()
    except: pass
    return None

def extract_real_url(url):
    """Google Alerts wraps URLs en google.com/url?...&url=<real> — extraer la real."""
    import urllib.parse
    if "google.com/url" in url:
        qs = urllib.parse.urlparse(url).query
        params = urllib.parse.parse_qs(qs)
        real = params.get("url", [url])[0]
        return real
    return url

def parse_feed(xml_bytes):
    try:
        root = ET.fromstring(xml_bytes)
        ns = {"a": "http://www.w3.org/2005/Atom"}
        items = []
        # Atom
        if "Atom" in root.tag or root.tag.endswith("}feed"):
            for e in root.findall("a:entry", ns)[:8]:
                t = (e.findtext("a:title", namespaces=ns) or "").strip()
                l_el = e.find("a:link", ns)
                link = l_el.get("href", "") if l_el is not None else ""
                if t and link: items.append({"title": t, "link": extract_real_url(link)})
        # RSS
        else:
            for i in root.findall(".//item")[:8]:
                t = (i.findtext("title") or "").strip()
                l = (i.findtext("link") or "").strip()
                if t and l: items.append({"title": t, "link": l})
        return items
    except: return []

def send_digest(items):
    if not items:
        log("Sin trends nuevos hoy. No se envía digest.")
        return

    lines = ["📊 *DIGEST TRENDS IA — HOY*\n"]
    for i, item in enumerate(items[:10], 1):
        emoji = "🚨" if item["priority"] >= 9 else "⚡" if item["priority"] >= 7 else "📌"
        lines.append(f"{emoji} *{i}. {item['source']}*")
        lines.append(f"{item['title'][:90]}")
        lines.append(f"🔗 {item['link']}\n")

    lines.append("💬 ¿Escribo alguno para el blog? Respóndeme con el número (puedes decir varios, ej: 1 y 3).")

    msg = "\n".join(lines)
    url = f"https://api.telegram.org/bot{KIMO_BOT_TOKEN}/sendMessage"
    data = json.dumps({
        "chat_id": KIMO_CHAT_ID,
        "text": msg,
        "parse_mode": "Markdown"
    }).encode()
    try:
        req = urllib.request.Request(url, data=data,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=8) as r:
            resp = json.loads(r.read())
            return resp.get("ok", False)
    except Exception as e:
        log(f"Error Telegram: {e}")
        return False

# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    log("=== trend-digest iniciado ===")
    seen = load_seen()
    candidates = []

    for source in SOURCES:
        log(f"Revisando: {source['name']}")
        xml = fetch_feed(source["url"])
        if not xml:
            log("  ❌ Sin respuesta")
            continue

        items = parse_feed(xml)
        log(f"  {len(items)} items")

        for item in items[:8]:
            iid = item_id(item["link"])
            if iid in seen:
                continue

            seen[iid] = {
                "source": source["name"],
                "title": item["title"][:80],
                "seen_at": datetime.now(timezone.utc).isoformat()
            }

            full = item["title"]
            if not is_relevant(full, source["keywords"]):
                continue

            candidates.append({
                "source": source["name"],
                "title": item["title"],
                "link": item["link"],
                "priority": source["priority"]
            })

    # Ordenar por prioridad y limitar a 5
    candidates.sort(key=lambda x: x["priority"], reverse=True)
    top = candidates[:10]
    log(f"Trends nuevos relevantes: {len(candidates)} → enviando top {len(top)}")

    ok = send_digest(top)
    log(f"Digest enviado: {'✅' if ok else '❌'}")

    # Limpiar seen >7 días
    cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()[:10]
    seen = {k: v for k, v in seen.items() if v.get("seen_at", "")[:10] >= cutoff}
    save_seen(seen)

    log("=== Fin ===\n")

if __name__ == "__main__":
    main()
