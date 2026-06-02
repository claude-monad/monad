#!/usr/bin/env python3
"""Monad cluster dashboard — a lean, read-only fleet view.

Single-file, stdlib-only HTTP server. Shows:
  - Nomad nodes (status / eligibility / drain / class)
  - Nomad jobs + a running-allocation count
  - mesh peers (best-effort, from `tailscale status --json`: hosts named agent-*)
  - the last ~50 cluster events (logs/events.jsonl)
  - the fleet backlog (fleet/BACKLOG.md rows + each project's live status)

Data sources: the Nomad HTTP API ($NOMAD_ADDR) and this git repo (which a background
thread `git pull`s every REFRESH_SECS so committed state — events, backlog — stays fresh).

Env:
  NOMAD_ADDR    Nomad API base (default http://100.75.75.39:4646)
  DASH_PORT     listen port (default 8088)
  REPO_DIR      repo root (default: two levels up from this file)
  REFRESH_SECS  git pull interval (default 60)
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
    for cmd in (["tailscale", "status", "--json"], ["sudo", "tailscale", "status", "--json"]):
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


def events(limit=50):
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


def state():
    return {
        "generated": time.strftime("%Y-%m-%d %H:%M:%SZ", time.gmtime()),
        "nomad_addr": NOMAD_ADDR,
        "nodes": nodes(),
        "jobs": jobs(),
        "peers": mesh_peers(),
        "events": events(),
        "backlog": backlog(),
    }


def repo_puller():
    while True:
        try:
            subprocess.run(["git", "-C", REPO_DIR, "pull", "--ff-only"],
                           capture_output=True, timeout=30)
        except Exception:
            pass
        time.sleep(REFRESH_SECS)


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
</style></head><body>
<header><h1>Monad cluster</h1>
<span class="muted" id="meta"></span>
<span class="muted">auto-refresh 15s · read-only</span></header>
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
 const evs=tbl(['time','node','source','action','result'],s.events.map(e=>
   `<tr class="ev"><td>${esc((e.ts||'').replace('T',' ').replace('Z',''))}</td><td>${esc(e.node)}</td><td>${esc(e.source)}</td><td>${esc(e.action||e.raw||'')}</td><td>${statusPill(e.result)}</td></tr>`));
 document.getElementById('app').innerHTML=
   `<section><h2>Nodes</h2>${nodes}</section>`+
   `<section><h2>Mesh peers</h2>${peers}</section>`+
   `<section class="full"><h2>Backlog</h2>${back}</section>`+
   `<section><h2>Jobs</h2>${jobs}</section>`+
   `<section class="full"><h2>Recent events</h2>${evs}</section>`;
}
load();setInterval(load,15000);
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

    def do_GET(self):
        if self.path.rstrip("/") in ("", "/index.html") or self.path == "/":
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif self.path.startswith("/api/state"):
            self._send(200, json.dumps(state()), "application/json")
        elif self.path == "/healthz":
            self._send(200, "ok", "text/plain")
        else:
            self._send(404, "not found", "text/plain")


def main():
    threading.Thread(target=repo_puller, daemon=True).start()
    print(f"[dashboard] serving on :{PORT} (nomad={NOMAD_ADDR}, repo={REPO_DIR})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
