#!/usr/bin/env python3
"""gateway.py — a codex worker's Tailscale text front door.

The codex worker analogue of conductor/gateway.py. OpenAI's Codex CLI has no
`remote-control` command (that is Claude-Code-specific), so codex workers cannot
register a session in the Claude app. Instead, this always-on HTTP service —
bound to the node's Tailscale IP — forwards plain-text requests to a single,
continuity-preserving headless `codex exec` session and returns its text reply.
This is "door 1": reach a codex worker as text from curl, a script, or a phone.

("Door 2" is an interactive tmux session attached over Tailscale SSH — see
start-codex-worker.sh. Two doors, one codex brain, mirroring the conductor.)

Endpoints
  GET  /            usage
  GET  /health      JSON: uptime, last query time, node id
  POST /ask         body = raw text OR {"text": "..."}  ->  {"reply": "..."}
                    (text/plain bodies get a text/plain reply, for curl-friendliness)

Design (mirrors conductor/gateway.py)
  * Continuity: one evolving codex thread. The first turn is `codex exec`; every
    later turn is `codex exec resume --last`, so the owner can carry a thread.
    Codex (unlike Claude's --session-id) does not let us pin a chosen id; because
    requests are serialized in a fixed workdir, `--last` reliably targets our own
    thread. Send '/reset' as the body to start a fresh thread.
  * Account-singularity: requests are SERIALIZED behind a lock — at most one codex
    process at a time (a node's codex shares one ChatGPT/OpenAI login).
  * Boundary: bind to the Tailscale IP only (private tailnet), never 0.0.0.0. An
    optional shared token (CODEX_TOKEN) adds a second check.

Env
  CODEX_BIND       ip to bind (default: `tailscale ip -4` first address)
  CODEX_PORT       port (default 8300)
  CODEX_WORKDIR    cwd for codex (default: the monad repo root)
  CODEX_BIN        codex binary (default: codex, falling back to /snap/bin/codex)
  CODEX_SANDBOX    "bypass" (default, full access, matches `codex --yolo`) or one of
                   codex's --sandbox modes: read-only | workspace-write | danger-full-access
  CODEX_MODEL      optional -m <model> override
  CODEX_PREAMBLE   optional path to a persona/system file prepended to the FIRST turn
                   (default codex-worker/CODEX.md if present)
  CODEX_STATE      state dir for the session marker + last-message file
                   (default codex-worker/.state)
  CODEX_TOKEN      optional shared secret; if set, requests must send
                   `Authorization: Bearer <token>` or `?token=`
  CODEX_TIMEOUT    per-request codex wall-clock seconds (default 600)
"""
from __future__ import annotations
import json, os, shutil, subprocess, threading, time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
MONAD_ROOT = os.path.abspath(os.path.join(HERE, ".."))

WORKDIR   = os.environ.get("CODEX_WORKDIR", MONAD_ROOT)
SANDBOX   = os.environ.get("CODEX_SANDBOX", "bypass")
MODEL     = os.environ.get("CODEX_MODEL", "")
PREAMBLE  = os.environ.get("CODEX_PREAMBLE", os.path.join(HERE, "CODEX.md"))
STATE_DIR = os.environ.get("CODEX_STATE", os.path.join(HERE, ".state"))
TOKEN     = os.environ.get("CODEX_TOKEN", "")
TIMEOUT   = int(os.environ.get("CODEX_TIMEOUT", "600"))
PORT      = int(os.environ.get("CODEX_PORT", "8300"))

STARTED_MARK = os.path.join(STATE_DIR, "started")
LAST_MSG     = os.path.join(STATE_DIR, "last-message.txt")

_lock = threading.Lock()
_state = {"started": time.time(), "last_query": None, "queries": 0}


def log(*a):
    print("[codex-worker]", *a, flush=True)


_codex_bin_cache = []


def _works(path: str) -> bool:
    if not path:
        return False
    try:
        r = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=20)
        return r.returncode == 0 and "codex" in (r.stdout + r.stderr).lower()
    except Exception:
        return False


def codex_bin() -> str:
    """First codex binary that actually runs. The npm wrapper can be present but
    broken (missing platform dep) while the snap build works — so we VALIDATE."""
    if _codex_bin_cache:
        return _codex_bin_cache[0]
    candidates = [os.environ.get("CODEX_BIN", ""), shutil.which("codex"),
                  "/snap/bin/codex", "/usr/local/bin/codex"]
    for c in candidates:
        if _works(c):
            _codex_bin_cache.append(c)
            return c
    # nothing validated — fall back to PATH lookup so the error is visible
    fallback = shutil.which("codex") or "/snap/bin/codex"
    _codex_bin_cache.append(fallback)
    return fallback


def default_bind() -> str:
    try:
        out = subprocess.run(["tailscale", "ip", "-4"], capture_output=True,
                             text=True, timeout=10).stdout
        for line in out.splitlines():
            if line.strip():
                return line.strip()
    except Exception:
        pass
    return "127.0.0.1"


def node_id() -> str:
    try:
        return subprocess.run(["hostname"], capture_output=True, text=True,
                              timeout=5).stdout.strip() or "codex-worker"
    except Exception:
        return "codex-worker"


def reset_session():
    for p in (STARTED_MARK, LAST_MSG):
        try:
            os.remove(p)
        except Exception:
            pass


def _sandbox_args() -> list[str]:
    if SANDBOX == "bypass":
        return ["--dangerously-bypass-approvals-and-sandbox"]
    # any explicit codex sandbox mode, run low-friction automatic
    return ["--sandbox", SANDBOX, "--full-auto"]


def _first_turn_preamble() -> str:
    """Persona/system text prepended ONLY to the first turn of a fresh thread."""
    if PREAMBLE and os.path.isfile(PREAMBLE):
        try:
            return open(PREAMBLE).read().strip()
        except Exception:
            return ""
    return ""


def ask_codex(text: str) -> tuple[str, int]:
    """Run one headless codex turn in this worker's thread. Serialized."""
    os.makedirs(STATE_DIR, exist_ok=True)
    cx = codex_bin()
    env = dict(os.environ)
    env.setdefault("NOMAD_ADDR", "http://%s:4646" % default_bind())

    def build(resume: bool, prompt: str) -> list[str]:
        # exec-level flags (sandbox, cwd, output, git-check) MUST precede the
        # `resume` subcommand; only `--last` and the prompt follow it.
        cmd = [cx, "exec"]
        cmd += _sandbox_args() + ["--skip-git-repo-check", "--cd", WORKDIR,
                                  "-o", LAST_MSG]
        if MODEL:
            cmd += ["-m", MODEL]
        if resume:
            cmd += ["resume", "--last"]
        cmd += [prompt]
        return cmd

    with _lock:
        _state["last_query"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        _state["queries"] += 1
        resume = os.path.isfile(STARTED_MARK)
        prompt = text
        if not resume:
            pre = _first_turn_preamble()
            if pre:
                prompt = pre + "\n\n---\n\n" + text
        try:
            if os.path.isfile(LAST_MSG):
                os.remove(LAST_MSG)
        except Exception:
            pass
        try:
            r = subprocess.run(build(resume, prompt), cwd=WORKDIR, env=env,
                               capture_output=True, text=True, timeout=TIMEOUT)
            if resume and r.returncode != 0 and "session" in (r.stdout + r.stderr).lower() \
               and ("no " in (r.stdout + r.stderr).lower() or "not found" in (r.stdout + r.stderr).lower()):
                # the prior thread was lost (e.g. fresh host) — start a new one
                reset_session()
                r = subprocess.run(build(False, text), cwd=WORKDIR, env=env,
                                   capture_output=True, text=True, timeout=TIMEOUT)
            open(STARTED_MARK, "w").write("1")
            # Prefer the clean final-message file; fall back to stdout.
            out = ""
            try:
                if os.path.isfile(LAST_MSG):
                    out = open(LAST_MSG).read().strip()
            except Exception:
                out = ""
            if not out:
                out = (r.stdout or "").strip()
            if r.returncode != 0:
                err = (r.stderr or "").strip()
                return (out + "\n" + err).strip() or "(codex exited %d, no output)" % r.returncode, r.returncode
            return out, 0
        except subprocess.TimeoutExpired:
            return "(codex worker timed out after %ds — try a narrower ask)" % TIMEOUT, 124
        except Exception as e:
            return "(codex worker error: %s)" % e, 1


USAGE = """Codex worker — text front door (Tailscale)

  POST /ask    body: raw text, or JSON {"text": "..."}    -> the worker's reply
  GET  /health                                            -> status JSON
  GET  /                                                  -> this help

Example:
  curl -s -X POST http://%s:%d/ask -d 'summarize what you are working on'

Continuity: every /ask continues the SAME codex thread. Send the word '/reset'
as the body to start a fresh thread.
"""


def authorized(handler) -> bool:
    if not TOKEN:
        return True
    auth = handler.headers.get("Authorization", "")
    if auth == "Bearer " + TOKEN:
        return True
    q = parse_qs(urlparse(handler.path).query)
    return q.get("token", [""])[0] == TOKEN


class H(BaseHTTPRequestHandler):
    server_version = "CodexWorker/1.0"

    def _send(self, code, body, ctype="text/plain"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass  # quiet; we log our own

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            body = json.dumps({
                "status": "up",
                "node": node_id(),
                "uptime_s": int(time.time() - _state["started"]),
                "queries": _state["queries"],
                "last_query": _state["last_query"],
                "workdir": WORKDIR,
                "sandbox": SANDBOX,
            }, indent=2)
            return self._send(200, body, "application/json")
        if path == "/":
            return self._send(200, USAGE % (default_bind(), PORT))
        return self._send(404, "not found\n")

    def do_POST(self):
        if urlparse(self.path).path != "/ask":
            return self._send(404, "not found\n")
        if not authorized(self):
            return self._send(401, "unauthorized\n")
        n = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        ctype = self.headers.get("Content-Type", "")
        text = raw
        if "application/json" in ctype:
            try:
                text = json.loads(raw).get("text", "")
            except Exception:
                text = raw
        text = (text or "").strip()
        if not text:
            return self._send(400, "empty request\n")
        if text == "/reset":
            reset_session()
            return self._send(200, "codex thread reset.\n")
        log("ask:", text[:120].replace("\n", " "))
        reply, rc = ask_codex(text)
        log("rc=%d reply_len=%d" % (rc, len(reply)))
        if "application/json" in ctype:
            return self._send(200, json.dumps({"reply": reply, "rc": rc}), "application/json")
        return self._send(200, reply + "\n")


def main():
    bind = os.environ.get("CODEX_BIND", default_bind())
    httpd = ThreadingHTTPServer((bind, PORT), H)
    log("codex worker gateway on http://%s:%d  (node=%s, workdir=%s, sandbox=%s)"
        % (bind, PORT, node_id(), WORKDIR, SANDBOX))
    log("codex bin:", codex_bin())
    log("auth:", "token required" if TOKEN else "tailnet-only (no token)")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
