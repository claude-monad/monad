#!/usr/bin/env python3
"""codex-tui — a minimal web chat to talk to self-hosted Codex over the tailnet.

Codex has no cloud remote-control relay (its `remote-control` is a LOCAL unix socket for IDE
integration), so the ChatGPT desktop/iOS app can't natively attach to a remote Codex CLI.
This gives a native-feeling browser chat instead, reachable from desktop or iOS Safari at
this node's Tailscale IP. Conversation continuity uses `codex exec resume <session-id>`.

Env: CODEX_TUI_PORT (8090), CODEX_BIN (codex), CODEX_HOME (creds dir), CODEX_TUI_WORKDIR,
     CODEX_TUI_PREAMBLE (prepended on the first turn of a chat), CODEX_TUI_LABEL,
     CODEX_TUI_DEFAULT_SESSION.
"""
import json, os, re, subprocess, tempfile, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT     = int(os.environ.get("CODEX_TUI_PORT", "8090"))
CODEX    = os.environ.get("CODEX_BIN", "codex")
WORKDIR  = os.environ.get("CODEX_TUI_WORKDIR", "/tmp/codex-tui-work")
TIMEOUT  = int(os.environ.get("CODEX_TUI_TIMEOUT", "600"))
PREAMBLE = os.environ.get("CODEX_TUI_PREAMBLE", "")
LABEL    = os.environ.get("CODEX_TUI_LABEL", "Codex TUI")
DEFAULT_SESSION = os.environ.get("CODEX_TUI_DEFAULT_SESSION", "default")
os.makedirs(WORKDIR, exist_ok=True)
if os.environ.get("CODEX_HOME"):
    os.environ["CODEX_HOME"] = os.environ["CODEX_HOME"]

SESSIONS = {}          # chat name -> codex session id (UUID)
LOCK = threading.Lock()
# Persist the name->session-id map so a tui restart (alloc reschedule, node move) keeps
# conversation continuity — e.g. the 'lrc' tracker session survives without re-priming.
STATE = os.environ.get("CODEX_TUI_STATE", os.path.join(WORKDIR, "sessions.json"))
try:
    with open(STATE) as f:
        SESSIONS.update(json.load(f))
    print(f"[codex-tui] restored {len(SESSIONS)} session(s) from {STATE}", flush=True)
except Exception:
    pass

def save_sessions():
    try:
        tmp = STATE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(SESSIONS, f)
        os.replace(tmp, STATE)
    except Exception:
        pass
# `codex exec` accepts -C (cwd); `codex exec resume` does NOT (it keeps the session's cwd).
COMMON = ["--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check"]

def run_codex(name, message):
    with LOCK:
        sid = SESSIONS.get(name)
    last = tempfile.mktemp(suffix=".txt")
    prompt = message
    if not sid and PREAMBLE:
        prompt = PREAMBLE + "\n\n---\n\n" + message
    if sid:
        # resume keeps the session's cwd (no -C); options before the SESSION_ID + prompt.
        cmd = [CODEX, "exec", "resume"] + COMMON + ["-o", last, sid, message]
    else:
        cmd = [CODEX, "exec"] + COMMON + ["-C", WORKDIR, "-o", last, prompt]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
        out = (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return {"reply": f"(codex timed out after {TIMEOUT}s)", "session": sid}
    m = re.search(r"session id:\s*([0-9a-fA-F-]{8,})", out)
    if m:
        with LOCK:
            SESSIONS[name] = m.group(1)
            save_sessions()
    reply = ""
    try:
        with open(last) as f:
            reply = f.read().strip()
        os.unlink(last)
    except Exception:
        reply = out[-3000:]
    return {"reply": reply or "(no output)", "session": SESSIONS.get(name)}

PAGE = """<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>__LABEL__</title><style>
body{font-family:-apple-system,system-ui,monospace;margin:0;background:#0b0e14;color:#d7dce5}
header{padding:10px 14px;background:#11151f;border-bottom:1px solid #232a39;font-weight:600}
header input{background:#1a2130;color:#d7dce5;border:1px solid #2a3346;border-radius:6px;padding:4px 8px;font-size:14px}
#log{padding:12px;overflow:auto;height:calc(100vh - 150px)}
.msg{margin:8px 0;white-space:pre-wrap;word-wrap:break-word;line-height:1.4}
.u{color:#7fd1ff}.a{color:#b9f5c0}.meta{color:#5b6680;font-size:12px}
footer{position:fixed;bottom:0;left:0;right:0;display:flex;gap:8px;padding:10px;background:#11151f;border-top:1px solid #232a39}
textarea{flex:1;background:#1a2130;color:#d7dce5;border:1px solid #2a3346;border-radius:8px;padding:10px;font-size:15px;resize:none;height:46px}
button{background:#2d6cdf;color:#fff;border:0;border-radius:8px;padding:0 18px;font-size:15px}
button:disabled{opacity:.5}
</style></head><body>
<header>__LABEL__ &middot; session <input id=sess value="__DEFAULT_SESSION__" size=18></header>
<div id=log></div>
<footer><textarea id=in placeholder="message codex…" autofocus></textarea><button id=send>Send</button></footer>
<script>
const log=document.getElementById('log'),inp=document.getElementById('in'),btn=document.getElementById('send'),sess=document.getElementById('sess');
function add(cls,who,txt){const d=document.createElement('div');d.className='msg '+cls;d.innerHTML='<span class=meta>'+who+'</span>\\n'+txt.replace(/</g,'&lt;');log.appendChild(d);log.scrollTop=log.scrollHeight;}
async function send(){const t=inp.value.trim();if(!t)return;inp.value='';add('u','you',t);btn.disabled=true;add('meta','codex','…thinking');
 try{const r=await fetch('/api/send',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({session:sess.value||'default',message:t})});
 const j=await r.json();log.lastChild.remove();add('a','codex',j.reply||'(no reply)');}catch(e){log.lastChild.remove();add('a','error',''+e);}btn.disabled=false;inp.focus();}
btn.onclick=send;inp.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();send();}});
</script></body></html>""".replace("__LABEL__", LABEL).replace("__DEFAULT_SESSION__", DEFAULT_SESSION)

class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code); self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path in ("/", "/index.html"): self._send(200, PAGE, "text/html; charset=utf-8")
        elif self.path == "/health": self._send(200, "ok", "text/plain")
        elif self.path == "/api/sessions": self._send(200, json.dumps(dict(SESSIONS)))
        else: self._send(404, "not found", "text/plain")
    def do_POST(self):
        if self.path != "/api/send": return self._send(404, "not found", "text/plain")
        n = int(self.headers.get("content-length", 0))
        try: d = json.loads(self.rfile.read(n) or b"{}")
        except Exception: d = {}
        msg = (d.get("message") or "").strip()
        if not msg: return self._send(400, json.dumps({"reply": "(empty message)"}))
        self._send(200, json.dumps(run_codex(d.get("session", "default"), msg)))
    def log_message(self, *a): pass

if __name__ == "__main__":
    print(f"[codex-tui] serving on :{PORT} (codex={CODEX}, workdir={WORKDIR})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
