#!/usr/bin/env python3
"""mesh-relay — a reliable real-time message bus for inter-LLM communication.

Why this exists: the tsnet P2P sidecar can DISCOVER peers but ephemeral tsnet nodes fail to
establish data connections to each other (outbound dial times out → 502). So instead of N×N
ephemeral-node dialing, agents talk through ONE relay reachable over the hosts' regular,
known-good Tailscale network. Real-time is via long-poll: GET /recv blocks until a message
arrives, so a reactive agent loop reacts in ~the time it takes to deliver, not a poll interval.

Endpoints:
  POST /register   {name}                 announce presence (also implicit on send/recv)
  GET  /peers[?self=NAME]                  [{name, online, age_s}]  (online = seen < 90s)
  POST /send       {from,to,body}          deliver to one agent, or to "all" (broadcast)
  GET  /recv?agent=NAME[&wait=SECONDS]     long-poll: returns [{from,body,ts}], draining inbox
  GET  /history?agent=NAME[&n=N]           recent delivered msgs (debug, non-draining)
  GET  /health                             ok

Env: MESH_RELAY_PORT (8477). In-memory (messages are transient; a restart clears queues).
"""
import json, os, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(os.environ.get("MESH_RELAY_PORT", "8477"))
ONLINE_WINDOW = 90  # seconds since last contact to count as "online"

LOCK = threading.Condition()
INBOX = {}      # agent -> [msg, ...] undelivered
SEEN = {}       # agent -> last_contact_epoch
HISTORY = {}    # agent -> [msg, ...] recent delivered (capped), for debugging


def touch(name):
    if name:
        SEEN[name] = time.time()


def deliver(msg, to):
    INBOX.setdefault(to, []).append(msg)
    h = HISTORY.setdefault(to, [])
    h.append(msg)
    del h[:-50]


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(b)))
        self.end_headers()
        try:
            self.wfile.write(b)
        except Exception:
            pass

    def _body(self):
        n = int(self.headers.get("content-length", 0) or 0)
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return {}

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/health":
            return self._send(200, "ok", "text/plain")
        if u.path == "/peers":
            me = (q.get("self") or [""])[0]
            with LOCK:
                touch(me)
                now = time.time()
                out = [{"name": n, "online": (now - t) < ONLINE_WINDOW, "age_s": round(now - t, 1)}
                       for n, t in sorted(SEEN.items()) if n != me]
            return self._send(200, json.dumps(out))
        if u.path == "/history":
            name = (q.get("agent") or [""])[0]
            n = int((q.get("n") or ["20"])[0])
            with LOCK:
                out = list(HISTORY.get(name, []))[-n:]
            return self._send(200, json.dumps(out))
        if u.path == "/recv":
            name = (q.get("agent") or [""])[0]
            wait = float((q.get("wait") or ["0"])[0])
            if not name:
                return self._send(400, json.dumps({"error": "agent required"}))
            deadline = time.time() + min(wait, 60)
            with LOCK:
                touch(name)
                while True:
                    out = INBOX.get(name) or []
                    if out or time.time() >= deadline:
                        INBOX[name] = []
                        break
                    LOCK.wait(timeout=max(0.1, deadline - time.time()))
            return self._send(200, json.dumps(out))
        return self._send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        u = urlparse(self.path)
        d = self._body()
        if u.path == "/register":
            with LOCK:
                touch(d.get("name", ""))
            return self._send(204, b"")
        if u.path == "/send":
            frm, to, body = d.get("from", "?"), d.get("to", ""), d.get("body", "")
            if not to or not body:
                return self._send(400, json.dumps({"error": "to and body required"}))
            msg = {"from": frm, "body": body, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
            with LOCK:
                touch(frm)
                if to == "all":
                    targets = [n for n in SEEN if n != frm]
                    for t in targets:
                        deliver(dict(msg), t)
                else:
                    deliver(dict(msg), to)
                LOCK.notify_all()
            return self._send(204, b"")
        return self._send(404, json.dumps({"error": "not found"}))

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print(f"[mesh-relay] listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
