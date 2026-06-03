#!/usr/bin/env python3
"""Monad cluster dashboard — a lean, read-only fleet view.

Single-file, stdlib-only HTTP server. Shows:
  - Nomad nodes (status / eligibility / drain / class)
  - Nomad jobs + a running-allocation count
  - mesh peers (best-effort, from `tailscale status --json`: hosts named agent-*)
  - the last ~50 cluster events (logs/events.jsonl), with a Server-Sent Events stream
  - the fleet backlog (fleet/BACKLOG.md rows + each project's live status)
  - fleet foreman status (Nomad var fleet/status)

Data sources: the Nomad HTTP API ($NOMAD_ADDR) and this git repo (which a background
thread `git pull`s every REFRESH_SECS so committed state — events, backlog — stays fresh).

Env:
  NOMAD_ADDR    Nomad API base (default http://100.75.75.39:4646)
  DASH_PORT     listen port (default 8088)
  REPO_DIR      repo root (default: two levels up from this file)
  REFRESH_SECS  git pull interval (default 60)
  EVENT_STREAM_SECS  event-stream check interval (default 5)
"""
import json
import os
import re
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NOMAD_ADDR = os.environ.get("NOMAD_ADDR", "http://100.75.75.39:4646").rstrip("/")
PORT = int(os.environ.get("DASH_PORT", "8088"))
REPO_DIR = os.environ.get(
    "REPO_DIR", os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
)
REFRESH_SECS = int(os.environ.get("REFRESH_SECS", "60"))
EVENT_LIMIT = int(os.environ.get("EVENT_LIMIT", "50"))
EVENT_STREAM_SECS = int(os.environ.get("EVENT_STREAM_SECS", "5"))

# ── chat: talk to Claude instances on the tailnet ──────────────────────────────
# Each chattable "brain" is a node running the conductor-style chat gateway
# (conductor/gateway.py): POST <url>/ask {"text": "..."} -> {"reply": "..."}, with
# per-gateway conversation continuity. The conductor is always target 0; other nodes
# expose the same gateway on :8200 once node-chat-gateway is deployed there. Mesh
# agents (agent-* tailnet peers) are reachable async via their sidecar (POST :8472/msg).
CHAT_TIMEOUT = int(os.environ.get("CHAT_TIMEOUT", "300"))
CONDUCTOR_URL = os.environ.get("CONDUCTOR_URL", "http://100.125.210.126:8200").rstrip("/")
# name -> gateway base url. Extend via env GATEWAYS="name=url,name=url".
GATEWAYS = {"conductor": CONDUCTOR_URL}
for _kv in os.environ.get("GATEWAYS", "").split(","):
    if "=" in _kv:
        _k, _v = _kv.split("=", 1)
        GATEWAYS[_k.strip()] = _v.strip().rstrip("/")
MESH_PORT = int(os.environ.get("MESH_PORT", "8472"))


def _post_json(url, payload, timeout):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or "{}")


def _gateway_up(url):
    try:
        with urllib.request.urlopen(url + "/health", timeout=4) as r:
            return r.status == 200
    except Exception:
        return False


def chat_targets():
    """Discover chattable instances: node gateways (brains) + mesh agents (async)."""
    out = []
    for name, url in GATEWAYS.items():
        out.append({
            "id": name, "label": name, "url": url,
            "kind": "brain" if name == "conductor" else "node",
            "up": _gateway_up(url),
        })
    for p in (cached_state().get("peers") or []):
        if str(p.get("name", "")).startswith("agent-"):
            out.append({
                "id": "mesh:" + p["name"], "label": p["name"], "kind": "agent",
                "ip": p.get("ip"), "up": bool(p.get("online")),
            })
    return out


def chat_route(target, text):
    """Send `text` to `target`, return the reply string. Raises on hard failure."""
    if target.startswith("mesh:"):
        name = target[5:]
        peer = next((p for p in (cached_state().get("peers") or [])
                     if p.get("name") == name), None)
        if not peer or not peer.get("ip"):
            raise RuntimeError(f"mesh agent {name} not found")
        _post_json(f"http://{peer['ip']}:{MESH_PORT}/msg",
                   {"from": "dashboard", "body": text}, 15)
        return f"(delivered to {name} — the mesh is asynchronous; its reply lands in that agent's mailbox, not here)"
    url = GATEWAYS.get(target)
    if not url:
        raise RuntimeError(f"unknown target '{target}'")
    r = _post_json(url + "/ask", {"text": text}, CHAT_TIMEOUT)
    return r.get("reply") or json.dumps(r)


def _nomad(path):
    """GET a Nomad API path, returning parsed JSON or None on failure."""
    try:
        with urllib.request.urlopen(f"{NOMAD_ADDR}{path}", timeout=8) as r:
            return json.loads(r.read().decode())
    except Exception:
        return None


def nodes():
    data = _nomad("/v1/nodes") or []
    out = []
    for n in data:
        out.append({
            "name": n.get("Name", "?"),
            "status": n.get("Status", "?"),
            "eligibility": n.get("SchedulingEligibility", "?"),
            "drain": bool(n.get("Drain", False)),
            "class": n.get("NodeClass") or "-",
            "dc": n.get("Datacenter", "-"),
        })
    return sorted(out, key=lambda x: x["name"])


def jobs():
    """Meaningful jobs only: drop dead jobs and per-dispatch batch children, and roll
    running-alloc counts (incl. dispatched children) up to the parent job."""
    data = _nomad("/v1/jobs") or []
    allocs = _nomad("/v1/allocations") or []

    def parent_of(jid):
        return jid.split("/dispatch-")[0] if jid and "/dispatch-" in jid else jid

    running = {}
    for a in allocs:
        if a.get("ClientStatus") == "running":
            p = parent_of(a.get("JobID", ""))
            running[p] = running.get(p, 0) + 1

    out = []
    for j in data:
        jid = j.get("ID", "")
        if "/dispatch-" in jid:
            continue  # collapse dispatched children into their parent
        if j.get("Status") == "dead" and not j.get("ParameterizedJob"):
            continue  # hide finished/stopped jobs (keep parameterized parents)
        out.append({
            "id": jid,
            "type": j.get("Type", "?"),
            "status": j.get("Status", "?"),
            "running": running.get(jid, 0),
        })
    return sorted(out, key=lambda x: (x["type"], x["id"]))


def mesh_peers():
    """Best-effort: tailnet hosts named agent-* via `tailscale status --json`."""
    for cmd in (["tailscale", "status", "--json"], ["sudo", "-n", "tailscale", "status", "--json"]):
        try:
            raw = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
            if raw.returncode != 0 or not raw.stdout.strip():
                continue
            st = json.loads(raw.stdout)
            peers = []
            for p in (st.get("Peer") or {}).values():
                host = p.get("HostName", "")
                if host.startswith("agent-"):
                    ips = p.get("TailscaleIPs") or []
                    peers.append({
                        "name": host,
                        "ip": ips[0] if ips else "?",
                        "online": bool(p.get("Online", False)),
                    })
            # include self if it's an agent
            self_host = (st.get("Self") or {}).get("HostName", "")
            if self_host.startswith("agent-"):
                ips = (st.get("Self") or {}).get("TailscaleIPs") or []
                peers.append({"name": self_host, "ip": ips[0] if ips else "?", "online": True})
            return sorted(peers, key=lambda x: x["name"])
        except Exception:
            continue
    return []


def events(limit=EVENT_LIMIT):
    path = os.path.join(REPO_DIR, "logs", "events.jsonl")
    try:
        with open(path, "r") as f:
            lines = f.readlines()[-limit:]
    except Exception:
        return []
    out = []
    for ln in reversed(lines):  # newest first
        ln = ln.strip()
        if not ln:
            continue
        try:
            out.append(json.loads(ln))
        except Exception:
            out.append({"raw": ln})
    return out


def backlog():
    """Parse fleet/BACKLOG.md table rows, enriched with each project's live status."""
    path = os.path.join(REPO_DIR, "fleet", "BACKLOG.md")
    rows = []
    try:
        with open(path) as f:
            text = f.read()
    except Exception:
        return rows
    link_re = re.compile(r"\[([^\]]+)\]\(projects/([^)]+)\)")
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 4 or cells[0] in ("Pri", "----:") or set(cells[0]) <= set("-: "):
            continue
        m = link_re.search(cells[1])
        slug = m.group(2)[:-3] if m and m.group(2).endswith(".md") else (m.group(2) if m else "")
        name = m.group(1) if m else cells[1]
        rows.append({
            "pri": cells[0],
            "project": name,
            "slug": slug,
            "why": cells[2],
            "status": project_status(slug) or cells[3],
        })
    return rows


def project_status(slug):
    if not slug:
        return None
    path = os.path.join(REPO_DIR, "fleet", "projects", f"{slug}.md")
    try:
        with open(path) as f:
            head = f.read(600)
    except Exception:
        return None
    s = re.search(r"^status:\s*(.+)$", head, re.M)
    o = re.search(r"^owner:\s*\"?([^\"\n]*)\"?$", head, re.M)
    st = s.group(1).strip() if s else None
    ow = o.group(1).strip() if o else ""
    return f"{st} ({ow})" if st and ow else st


def _project_entries(value):
    if not value or value == "none":
        return []
    out = []
    for raw in value.split(","):
        parts = raw.split(":", 3)
        if len(parts) == 4:
            out.append({
                "slug": parts[0],
                "status": parts[1],
                "owner": parts[2],
                "updated": parts[3],
            })
        elif raw:
            out.append({"slug": raw, "status": "?", "owner": "?", "updated": ""})
    return out


def foreman_status():
    data = _nomad("/v1/var/fleet/status") or {}
    items = data.get("Items") or {}
    if not items:
        return {"available": False, "active_projects": [], "blocked_projects": []}
    return {
        "available": True,
        "running": items.get("running", "?"),
        "target": items.get("target", "?"),
        "dispatched_this_cycle": items.get("dispatched_this_cycle", "0"),
        "updated": items.get("updated", ""),
        "backlog": {
            "todo": items.get("backlog_todo", "0"),
            "claimed": items.get("backlog_claimed", "0"),
            "building": items.get("backlog_building", "0"),
            "review": items.get("backlog_review", "0"),
            "blocked": items.get("backlog_blocked", "0"),
            "done": items.get("backlog_done", "0"),
        },
        "active_projects": _project_entries(items.get("active_projects", "")),
        "blocked_projects": _project_entries(items.get("blocked_projects", "")),
    }


def health_summary():
    """Read the fleet-health-rollup var (fleet/health-summary): the single rollup
    of the scattered per-monitor verdicts (raft/registry/checkout)."""
    data = _nomad("/v1/var/fleet/health-summary") or {}
    items = data.get("Items") or {}
    if not items:
        return {"available": False, "components": []}
    comps = []
    for pair in (items.get("components", "") or "").split(";"):
        if not pair or "=" not in pair:
            continue
        name, st = pair.split("=", 1)
        det = items.get("d_" + name.replace(":", "_"), "")
        comps.append({"name": name, "status": st, "detail": det})
    return {
        "available": True,
        "status": items.get("status", "?"),
        "raw_status": items.get("raw_status", ""),
        "acknowledged": items.get("acknowledged", "none"),
        "detail": items.get("detail", ""),
        "stale": items.get("stale", "none"),
        "foreman": items.get("foreman", ""),
        "updated": items.get("ts", ""),
        "components": comps,
    }


def capabilities():
    """Per-node engine capability matrix from Nomad vars `capability/<node>` (written by
    the cluster-capability sysbatch job). Honest: each node actually ran claude+codex."""
    stubs = _nomad("/v1/vars?prefix=capability/") or []
    out = []
    for s in stubs:
        path = s.get("Path", "")
        if not path.startswith("capability/"):
            continue
        full = _nomad("/v1/var/" + path) or {}
        it = full.get("Items", {})
        out.append({
            "node": it.get("node", path.split("/")[-1]),
            "claude": it.get("claude", "?"),
            "codex": it.get("codex", "?"),
            "user": it.get("user", ""),
            "ts": it.get("ts", ""),
        })
    return sorted(out, key=lambda x: x["node"])


def state():
    return {
        "generated": time.strftime("%Y-%m-%d %H:%M:%SZ", time.gmtime()),
        "nomad_addr": NOMAD_ADDR,
        "nodes": nodes(),
        "jobs": jobs(),
        "peers": mesh_peers(),
        "events": events(),
        "backlog": backlog(),
        "foreman_status": foreman_status(),
        "health_summary": health_summary(),
        "capabilities": capabilities(),
    }


# A cached snapshot so /api/state never blocks on data gathering (Nomad API +
# `tailscale status` can be slow, especially on the first call). A background thread
# refreshes it; requests just serve the latest cache. Starts as a valid empty shape.
_cache = {
    "generated": "warming…", "nomad_addr": NOMAD_ADDR,
    "nodes": [], "jobs": [], "peers": [], "events": [], "backlog": [],
    "foreman_status": {"available": False, "active_projects": [], "blocked_projects": []},
    "health_summary": {"available": False, "components": []},
    "capabilities": [],
}
_cache_lock = threading.Lock()
STATE_SECS = int(os.environ.get("STATE_SECS", "10"))


def state_refresher():
    global _cache
    tick = 0
    while True:
        # git-pull the repo clone every REFRESH_SECS so committed state stays fresh
        if tick % max(1, REFRESH_SECS // STATE_SECS) == 0:
            try:
                subprocess.run(["git", "-C", REPO_DIR, "pull", "--ff-only"],
                               capture_output=True, timeout=30)
            except Exception:
                pass
        try:
            snap = state()
            with _cache_lock:
                _cache = snap
        except Exception:
            pass
        tick += 1
        time.sleep(STATE_SECS)


def cached_state():
    with _cache_lock:
        return _cache


PAGE = """<!doctype html><html><head><meta charset="utf-8">
<title>Monad cluster</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{color-scheme:dark}
body{font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:0;background:#0d1117;color:#c9d1d9}
header{padding:14px 20px;background:#161b22;border-bottom:1px solid #30363d;display:flex;
  align-items:baseline;gap:14px;flex-wrap:wrap}
h1{font-size:17px;margin:0;color:#e6edf3}
.muted{color:#7d8590;font-size:12px}
main{padding:18px 20px;display:grid;gap:18px;grid-template-columns:repeat(auto-fit,minmax(360px,1fr))}
section{background:#161b22;border:1px solid #30363d;border-radius:8px;overflow:hidden}
h2{font-size:13px;text-transform:uppercase;letter-spacing:.05em;margin:0;padding:10px 14px;
  background:#1c2128;border-bottom:1px solid #30363d;color:#9da7b3}
table{width:100%;border-collapse:collapse}
td,th{padding:6px 14px;text-align:left;border-bottom:1px solid #21262d;vertical-align:top}
th{font-weight:600;color:#7d8590;font-size:11px;text-transform:uppercase}
tr:last-child td{border-bottom:0}
.pill{display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;font-weight:600}
.ok{background:#1a3326;color:#3fb950}.warn{background:#3a2d12;color:#d29922}
.bad{background:#3a1a1f;color:#f85149}.dim{background:#21262d;color:#8b949e}
.full{grid-column:1/-1}
code{font:12px ui-monospace,monospace;color:#a5d6ff}
.ev{font:12px ui-monospace,monospace}
#chat{margin:18px 20px 0;background:#161b22;border:1px solid #30363d;border-radius:8px}
#chat .bar{display:flex;gap:10px;align-items:center;padding:10px 14px;border-bottom:1px solid #30363d;background:#1c2128}
#chat select,#chat input,#chat button{font:13px inherit;background:#0d1117;color:#c9d1d9;border:1px solid #30363d;border-radius:6px;padding:7px 9px}
#chat input{flex:1}
#chat button{background:#238636;border-color:#238636;color:#fff;cursor:pointer;font-weight:600}
#chat button:disabled{opacity:.5;cursor:default}
#log{max-height:360px;overflow:auto;padding:12px 14px;display:flex;flex-direction:column;gap:10px}
.msg{max-width:82%;padding:8px 11px;border-radius:10px;white-space:pre-wrap;word-break:break-word}
.me{align-self:flex-end;background:#1f6feb;color:#fff}
.them{align-self:flex-start;background:#21262d}
.sys{align-self:center;color:#7d8590;font-size:12px;font-style:italic}
.who{font-size:11px;opacity:.7;margin-bottom:2px}
</style></head><body>
<header><h1>Monad cluster</h1>
<span class="muted" id="meta"></span>
<span class="muted">state refresh 30s · event stream · live chat</span></header>
<section id="chat">
<h2 style="display:flex;justify-content:space-between;align-items:center">Chat with a Claude instance
<span class="muted" id="chat-meta"></span></h2>
<div class="bar">
<select id="target" title="which Claude instance to talk to"></select>
<input id="msg" placeholder="Message… (Enter to send)" autocomplete="off">
<button id="send">Send</button>
</div>
<div id="log"><div class="msg sys">Pick a target and say hello. <b>conductor</b> is the always-on Claude brain that can inspect and act on the whole cluster. Node gateways and mesh agents appear here as they come online.</div></div>
</section>
<main id="app">loading…</main>
<script>
const pill=(t,c)=>`<span class="pill ${c}">${t}</span>`;
function statusPill(s){s=(s||'').toLowerCase();
  if(s.includes('running')||s.includes('ready')||s.includes('done'))return pill(s,'ok');
  if(s.includes('pending')||s.includes('building')||s.includes('claimed'))return pill(s,'warn');
  if(s.includes('dead')||s.includes('failed')||s.includes('blocked')||s.includes('down'))return pill(s,'bad');
  return pill(s||'?','dim');}
function tbl(cols,rows){return `<table><tr>${cols.map(c=>`<th>${c}</th>`).join('')}</tr>${rows.join('')}</table>`;}
function esc(x){return (x==null?'':String(x)).replace(/[&<>]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[m]));}
const STATE_REFRESH_MS=30000;
let eventStreamStarted=false;
function eventResult(e){return e.result||e.status||'';}
function eventAction(e){return e.action||e.event||e.raw||'';}
function eventNode(e){return e.node||e.agent||'';}
function renderEvents(events){
 const evs=tbl(['time','node','source','action','result'],(events||[]).map(e=>
   `<tr class="ev"><td>${esc((e.ts||'').replace('T',' ').replace('Z',''))}</td><td>${esc(eventNode(e))}</td><td>${esc(e.source)}</td><td>${esc(eventAction(e))}</td><td>${statusPill(eventResult(e))}</td></tr>`));
 const el=document.getElementById('events-body');
 if(el)el.innerHTML=evs;
 return evs;
}
function projectRows(rows){
 if(!rows||!rows.length)return '<p class="muted" style="padding:8px 14px">none</p>';
 return tbl(['project','status','owner','updated'],rows.map(p=>
   `<tr><td><code>${esc(p.slug)}</code></td><td>${statusPill(p.status)}</td><td>${esc(p.owner)}</td><td class="muted">${esc((p.updated||'').replace('T',' ').replace('Z',''))}</td></tr>`));
}
function healthPill(s){s=(s||'').toLowerCase();
  if(s==='healthy'||s==='ok')return pill(s,'ok');
  if(s==='warn'||s==='stale')return pill(s,'warn');
  if(s==='critical')return pill(s,'bad');
  return pill(s||'?','dim');}
function renderHealth(h){
 if(!h||!h.available)return '<p class="muted" style="padding:12px 14px">fleet/health-summary unavailable (fleet-health-rollup not run yet)</p>';
 const raw=(h.raw_status&&h.raw_status!==h.status)?` <span class="muted">(raw ${healthPill(h.raw_status)} incl. acknowledged)</span>`:'';
 const head=`<p style="padding:8px 14px 0">overall ${healthPill(h.status)}${raw} <span class="muted">${esc(h.detail)}</span></p>`;
 const ack=(h.acknowledged&&h.acknowledged!=='none')?`<p class="muted" style="padding:0 14px">acknowledged (owner-gated, excluded from top-line): ${esc(h.acknowledged)}</p>`:'';
 const rows=(h.components||[]).map(c=>
   `<tr><td><code>${esc(c.name)}</code></td><td>${healthPill(c.status)}</td><td class="muted">${esc(c.detail)}</td></tr>`);
 const t=tbl(['component','status','detail'],rows);
 const meta=`<p class="muted" style="padding:0 14px 8px">foreman: ${esc(h.foreman)} · updated ${esc((h.updated||'').replace('T',' ').replace('Z',''))}</p>`;
 return head+ack+t+meta;
}
function renderForeman(f){
 if(!f||!f.available)return '<p class="muted" style="padding:12px 14px">fleet/status unavailable</p>';
 const b=f.backlog||{};
 const buildersText=`${esc(f.running)}/${esc(f.target)}`;
 const buildersClass=String(f.running)===String(f.target)?'ok':'warn';
 const top=tbl(['builders','target','dispatched','updated'],[
   `<tr><td>${pill(buildersText,buildersClass)}</td><td>${esc(f.target)}</td><td>${esc(f.dispatched_this_cycle)}</td><td class="muted">${esc((f.updated||'').replace('T',' ').replace('Z',''))}</td></tr>`]);
 const counts=tbl(['todo','claimed','building','review','blocked','done'],[
   `<tr><td>${esc(b.todo)}</td><td>${esc(b.claimed)}</td><td>${esc(b.building)}</td><td>${esc(b.review)}</td><td>${esc(b.blocked)}</td><td>${esc(b.done)}</td></tr>`]);
 return `${top}${counts}<h2>Active projects</h2>${projectRows(f.active_projects)}<h2>Blocked projects</h2>${projectRows(f.blocked_projects)}`;
}
function connectEvents(){
 if(eventStreamStarted||!window.EventSource)return;
 eventStreamStarted=true;
 const es=new EventSource('api/events/stream');
 es.addEventListener('events',ev=>{
   try{renderEvents(JSON.parse(ev.data));}catch(e){}
 });
}
async function load(){
 let s;try{s=await (await fetch('api/state')).json();}catch(e){document.getElementById('app').textContent='fetch failed';return;}
 document.getElementById('meta').textContent=`${s.generated} · ${s.nomad_addr} · ${s.nodes.length} nodes · ${s.jobs.length} jobs · ${s.peers.length} mesh peers`;
 const nodes=tbl(['node','status','elig','class','dc'],s.nodes.map(n=>
   `<tr><td><b>${esc(n.name)}</b></td><td>${statusPill(n.status)}</td><td>${esc(n.eligibility)}${n.drain?' '+pill('drain','warn'):''}</td><td>${esc(n.class)}</td><td>${esc(n.dc)}</td></tr>`));
 const jobs=tbl(['job','type','status','run'],s.jobs.map(j=>
   `<tr><td><code>${esc(j.id)}</code></td><td>${esc(j.type)}</td><td>${statusPill(j.status)}</td><td>${j.running}</td></tr>`));
 const peers=s.peers.length?tbl(['agent','ip','online'],s.peers.map(p=>
   `<tr><td><b>${esc(p.name)}</b></td><td><code>${esc(p.ip)}</code></td><td>${p.online?pill('online','ok'):pill('offline','dim')}</td></tr>`))
   :'<p class="muted" style="padding:12px 14px">no mesh peers visible (tailscale status unavailable on host)</p>';
 const back=tbl(['#','project','status','why'],s.backlog.map(b=>
   `<tr><td>${esc(b.pri)}</td><td><b>${esc(b.project)}</b></td><td>${statusPill(b.status)}</td><td class="muted">${esc(b.why)}</td></tr>`));
 const capPill=(x)=>{x=x||'?';
   if(x==='ok')return pill('✓ ok','ok');
   if(x==='absent'||x==='not-authed'||x==='?')return pill(x==='?'?'untested':x,'dim');
   return pill(x,'bad');};   // ran-empty / error-rcN / timeout = honest failure
 const caps=(s.capabilities&&s.capabilities.length)
   ? tbl(['node','claude session','codex session','last tested'],s.capabilities.map(c=>
       `<tr><td><b>${esc(c.node)}</b></td><td>${capPill(c.claude)}</td><td>${capPill(c.codex)}</td><td class="muted">${esc((c.ts||'').replace('T',' ').replace('Z',''))}</td></tr>`))
   : '<p class="muted" style="padding:12px 14px">no capability reports yet — the cluster-capability job runs every 6h (force one with <code>nomad job periodic force cluster-capability</code>). ✓=ran a real autonomous math session; ran-empty/error/absent = honest failure.</p>';
 document.getElementById('app').innerHTML=
   `<section class="full"><h2>Node capabilities — autonomous math session (claude / codex)</h2>${caps}</section>`+
   `<section class="full"><h2>Cluster health</h2>${renderHealth(s.health_summary)}</section>`+
   `<section><h2>Nodes</h2>${nodes}</section>`+
   `<section><h2>Mesh peers</h2>${peers}</section>`+
   `<section class="full"><h2>Fleet foreman</h2>${renderForeman(s.foreman_status)}</section>`+
   `<section class="full"><h2>Backlog</h2>${back}</section>`+
   `<section><h2>Jobs</h2>${jobs}</section>`+
   `<section class="full"><h2>Recent events</h2><div id="events-body">${renderEvents(s.events)}</div></section>`;
 connectEvents();
}
load();setInterval(load,STATE_REFRESH_MS);

// ── chat ───────────────────────────────────────────────────────────────────
const _log=document.getElementById('log');
function chatAdd(cls,who,text){
 const d=document.createElement('div');d.className='msg '+cls;
 d.innerHTML=(who?`<div class="who">${esc(who)}</div>`:'')+esc(text);
 _log.appendChild(d);_log.scrollTop=_log.scrollHeight;return d;}
async function loadTargets(){
 try{const ts=await(await fetch('api/chat/targets')).json();
  const sel=document.getElementById('target');const cur=sel.value;
  sel.innerHTML=ts.map(t=>`<option value="${esc(t.id)}">${esc(t.label)} · ${esc(t.kind)}${t.up?'':' (down)'}</option>`).join('');
  if(cur&&ts.some(t=>t.id===cur))sel.value=cur;
  document.getElementById('chat-meta').textContent=ts.length+' target'+(ts.length===1?'':'s');
 }catch(e){}}
async function chatSend(){
 const inp=document.getElementById('msg'),btn=document.getElementById('send'),sel=document.getElementById('target');
 const text=inp.value.trim();if(!text)return;
 const target=sel.value||'conductor';
 chatAdd('me','you → '+target,text);inp.value='';btn.disabled=true;inp.disabled=true;
 const pend=chatAdd('sys','','…'+target+' is thinking');
 try{
  const r=await(await fetch('api/chat',{method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({target,text})})).json();
  pend.remove();
  if(r.error)chatAdd('sys','',target+' — error: '+r.error);
  else chatAdd('them',target,r.reply);
 }catch(e){pend.remove();chatAdd('sys','','network error: '+e);}
 btn.disabled=false;inp.disabled=false;inp.focus();}
document.getElementById('send').onclick=chatSend;
document.getElementById('msg').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();chatSend();}});
loadTargets();setInterval(loadTargets,30000);
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _stream_events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        self.wfile.write(b"retry: 5000\n\n")
        self.wfile.flush()
        last_payload = None
        while True:
            try:
                payload = json.dumps(events())
                if payload != last_payload:
                    self.wfile.write(f"event: events\ndata: {payload}\n\n".encode())
                    last_payload = payload
                else:
                    self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
                time.sleep(EVENT_STREAM_SECS)
            except (BrokenPipeError, ConnectionResetError):
                return
            except Exception:
                return

    def do_GET(self):
        if self.path.rstrip("/") in ("", "/index.html") or self.path == "/":
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif self.path.startswith("/api/state"):
            self._send(200, json.dumps(cached_state()), "application/json")
        elif self.path.startswith("/api/events/stream"):
            self._stream_events()
        elif self.path.startswith("/api/events"):
            self._send(200, json.dumps(events()), "application/json")
        elif self.path.startswith("/api/chat/targets"):
            self._send(200, json.dumps(chat_targets()), "application/json")
        elif self.path == "/healthz":
            self._send(200, "ok", "text/plain")
        else:
            self._send(404, "not found", "text/plain")

    def do_POST(self):
        if self.path.rstrip("/") == "/api/chat":
            try:
                n = int(self.headers.get("Content-Length", "0") or 0)
                body = json.loads(self.rfile.read(n) or "{}")
            except Exception:
                self._send(400, json.dumps({"error": "bad json"}), "application/json")
                return
            target = (body.get("target") or "conductor").strip()
            text = (body.get("text") or "").strip()
            if not text:
                self._send(400, json.dumps({"error": "empty message"}), "application/json")
                return
            try:
                reply = chat_route(target, text)
                self._send(200, json.dumps({"reply": reply, "target": target}),
                           "application/json")
            except Exception as e:
                self._send(200, json.dumps({"error": str(e)[:400], "target": target}),
                           "application/json")
        else:
            self._send(404, "not found", "text/plain")


def main():
    # Start serving immediately; the background refresher fills the cache within
    # STATE_SECS. _cache starts as a valid empty shape so the first request and the
    # page never error while data is still being gathered.
    threading.Thread(target=state_refresher, daemon=True).start()
    print(f"[dashboard] serving on :{PORT} (nomad={NOMAD_ADDR}, repo={REPO_DIR})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
