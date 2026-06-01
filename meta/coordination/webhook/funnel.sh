#!/usr/bin/env bash
# funnel.sh — run the webhook receiver and expose it via Tailscale Funnel.
# Self-healing like scripts/claudebox-server.sh: ensures the server is up and the funnel
# is published, so GitHub can reach a private tailnet node. Non-root.
#
#   GitHub  ->  https://<this-node>.<tailnet>.ts.net/hook  (Funnel, port 443)
#           ->  127.0.0.1:8089  (this receiver)  ->  rules -> emit task + dispatch
#
# Install (user cron):
#   (crontab -l 2>/dev/null; echo "*/5 * * * * $HOME/monad/meta/coordination/webhook/funnel.sh keepalive >> $HOME/nomad/webhook.log 2>&1") | crontab -
#
# Usage: funnel.sh [start|keepalive|stop|status|url]
#   Set DRY_RUN=1 to receive+log but not emit/dispatch (safe testing).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${WEBHOOK_PORT:-8089}"
LOG="$HOME/nomad/webhook-server.log"
PIDF="$HOME/nomad/webhook.pid"
export WEBHOOK_PORT="$PORT"
export WEBHOOK_SECRET_FILE="${WEBHOOK_SECRET_FILE:-$HOME/nomad/webhook.secret}"
export PATH="$HOME/bin:$PATH"

ts_name() { tailscale status --json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))" 2>/dev/null; }
url() { echo "https://$(ts_name)/hook"; }
server_up() { curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; }
funnel_up() { tailscale funnel status 2>/dev/null | grep -q "127.0.0.1:$PORT\|:$PORT"; }

start_server() {
  if server_up; then echo "[funnel] receiver already up on :$PORT"; return 0; fi
  [ -f "$WEBHOOK_SECRET_FILE" ] || { echo "[funnel] MISSING secret at $WEBHOOK_SECRET_FILE"; return 1; }
  echo "[funnel] starting receiver…"
  nohup python3 "$HERE/server.py" > "$LOG" 2>&1 &
  echo $! > "$PIDF"
  for _ in $(seq 1 15); do server_up && break; sleep 1; done
  server_up && echo "[funnel] receiver up (pid $(cat "$PIDF"))" || { echo "[funnel] FAILED"; tail -5 "$LOG"; return 1; }
}

start_funnel() {
  if funnel_up; then echo "[funnel] funnel already published"; return 0; fi
  echo "[funnel] publishing funnel 443 -> 127.0.0.1:$PORT …"
  tailscale funnel --bg "$PORT" 2>&1 | head -5 || {
    echo "[funnel] could not publish — check 'tailscale funnel' is permitted in the tailnet ACLs"; return 1; }
}

case "${1:-keepalive}" in
  start|keepalive) start_server && start_funnel && echo "[funnel] endpoint: $(url)" ;;
  stop)
    [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null && echo "receiver stopped" || echo "receiver not running"
    tailscale funnel --https=443 off 2>/dev/null || tailscale funnel reset 2>/dev/null || true
    echo "funnel off" ;;
  status)
    server_up && echo "receiver: UP ($(url))" || echo "receiver: DOWN"
    echo "--- tailscale funnel ---"; tailscale funnel status 2>&1 | head -20 ;;
  url) url ;;
  *) echo "usage: $0 [start|keepalive|stop|status|url]"; exit 2 ;;
esac
