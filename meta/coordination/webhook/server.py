#!/usr/bin/env python3
"""server.py — GitHub webhook receiver for the cluster (the "push" half of hybrid).

Public flow:  GitHub  ->  Tailscale Funnel (https://claudebox.<tailnet>.ts.net/hook)
              ->  this receiver on claudebox  ->  rules.match  ->  emit task + dispatch.

Security (this is a PUBLIC endpoint that can dispatch jobs):
  * every request MUST carry a valid X-Hub-Signature-256 (HMAC-SHA256 of the body with
    the shared secret); unsigned/bad-sig requests are rejected 401.
  * only repos that appear in the rule table are accepted; anything else is ignored.
  * actions are FIXED (a known job + a bounded scope string). Payload text is never
    executed; only fixed job names are dispatched.
  * delivery ids are de-duplicated (GitHub retries).

Env:
  WEBHOOK_SECRET       shared secret (or read from WEBHOOK_SECRET_FILE)
  WEBHOOK_SECRET_FILE  path to a file holding the secret (default ~/nomad/webhook.secret)
  WEBHOOK_PORT         local listen port (default 8089)
  NOMAD_ADDR           for dispatch (default http://<tailscale-ip>:4646)
  DRY_RUN              if set, log actions but do not emit/dispatch
"""
from __future__ import annotations
import hashlib
import hmac
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rules as R  # noqa: E402

MONAD_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TASK_SH = os.path.join(HERE, "..", "task.sh")
PORT = int(os.environ.get("WEBHOOK_PORT", "8089"))
DRY_RUN = bool(os.environ.get("DRY_RUN"))
_seen = set()  # delivery-id dedup (process-lifetime)


def log(*a):
    print("[webhook]", *a, flush=True)


def secret() -> bytes:
    s = os.environ.get("WEBHOOK_SECRET")
    if not s:
        path = os.environ.get("WEBHOOK_SECRET_FILE", os.path.expanduser("~/nomad/webhook.secret"))
        if os.path.isfile(path):
            s = open(path).read().strip()
    return (s or "").encode()


def valid_sig(body: bytes, header: str | None) -> bool:
    sec = secret()
    if not sec or not header or not header.startswith("sha256="):
        return False
    digest = hmac.new(sec, body, hashlib.sha256).hexdigest()
    return hmac.compare_digest("sha256=" + digest, header)


def changed_paths(event: str, payload: dict) -> list[str]:
    paths = []
    if event == "push":
        for c in payload.get("commits", []):
            paths += c.get("added", []) + c.get("modified", []) + c.get("removed", [])
    return sorted(set(paths))


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def execute(action: R.Action):
    """Hybrid: emit a durable task AND (if a job is named) dispatch immediately."""
    if DRY_RUN:
        log("DRY_RUN action:", action)
        return
    # 1) durable task (pull-loop safety net)
    run(["bash", TASK_SH, "emit", action.task_type, action.repo, action.scope])
    # 2) immediate push
    if action.job:
        r = run(["nomad", "job", "dispatch", "-detach",
                 "-meta", f"SCOPE={action.scope[:200]}", action.job])
        log("dispatch", action.job, "->", "ok" if r.returncode == 0 else r.stderr.strip()[:120])


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, msg="ok"):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(msg.encode())

    def log_message(self, *a):  # silence default noisy logging
        pass

    def do_GET(self):
        if self.path in ("/health", "/"):
            self._send(200, "cluster webhook receiver: ok")
        else:
            self._send(404, "not found")

    def do_POST(self):
        if self.path != "/hook":
            return self._send(404, "not found")
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 2_000_000:
            return self._send(400, "bad length")
        body = self.rfile.read(length)
        if not valid_sig(body, self.headers.get("X-Hub-Signature-256")):
            log("REJECT bad signature from", self.client_address[0])
            return self._send(401, "bad signature")
        delivery = self.headers.get("X-GitHub-Delivery", "")
        if delivery and delivery in _seen:
            return self._send(200, "duplicate ignored")
        _seen.add(delivery)
        event = self.headers.get("X-GitHub-Event", "")
        try:
            payload = json.loads(body)
        except Exception:
            return self._send(400, "bad json")
        repo = (payload.get("repository") or {}).get("full_name", "")
        action = payload.get("action")
        ctx = {"merged": bool((payload.get("pull_request") or {}).get("merged"))}
        paths = changed_paths(event, payload)

        actions = R.match(repo, event, action, paths, ctx)
        if not actions:
            return self._send(200, f"no rule ({repo} {event} {action})")
        for a in actions:
            log(f"{repo} {event} {action or ''} -> {a.task_type} ({a.job or 'queue-only'}): {a.scope}")
            execute(a)
        return self._send(200, f"kicked off {len(actions)} action(s)")


def main():
    log(f"listening on :{PORT}  dry_run={DRY_RUN}  secret={'set' if secret() else 'MISSING'}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
