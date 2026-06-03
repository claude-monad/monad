#!/usr/bin/env bash
# agent-ping.sh — test tsnet IPC with a running agent-* sidecar.
#
# Usage:
#   ./scripts/agent-ping.sh windesk                  # ping agent-windesk (default port 8472)
#   ./scripts/agent-ping.sh windesk "hello there"    # send a message body
#   ./scripts/agent-ping.sh windesk "" 8472           # explicit port
#
# The sidecar's MESH api lives on its Tailnet IP. This script looks up the IP
# by querying a LOCAL sidecar's /peers endpoint, or falls back to querying the
# Tailscale API directly.
#
# Requires: curl, tailscale (or a running local sidecar on LOCAL_PORT=8473)

set -euo pipefail

TARGET="${1:-}"
MESSAGE="${2:-ping from $(hostname) at $(date -u +%H:%M:%SZ)}"
MESH_PORT="${3:-8472}"
LOCAL_PORT="${LOCAL_PORT:-8473}"

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <agent-name> [message] [mesh-port]"
  echo "  agent-name: e.g. windesk (resolves to agent-windesk on the tailnet)"
  exit 1
fi

# Normalize name
if [[ "$TARGET" != agent-* ]]; then
  TARGET="agent-$TARGET"
fi

log() { echo "[agent-ping] $*" >&2; }

# ── Try local sidecar /peers first ─────────────────────────────────────────────
IP=""
if curl -sf "http://127.0.0.1:${LOCAL_PORT}/peers" --max-time 2 >/dev/null 2>&1; then
  PEERS_JSON=$(curl -sf "http://127.0.0.1:${LOCAL_PORT}/peers" --max-time 5)
  IP=$(echo "$PEERS_JSON" | python3 -c "
import sys, json
peers = json.load(sys.stdin)
for p in peers:
    if p.get('name','').lower() == '${TARGET}'.lower():
        print(p['ip']); break
" 2>/dev/null || true)
  [ -n "$IP" ] && log "found $TARGET via local sidecar: $IP"
fi

# ── Fall back to tailscale status ──────────────────────────────────────────────
if [ -z "$IP" ]; then
  if command -v tailscale >/dev/null 2>&1; then
    IP=$(tailscale status --json 2>/dev/null | python3 -c "
import sys, json
st = json.load(sys.stdin)
for v in st.get('Peer', {}).values():
    name = (v.get('HostName','') or '').lower()
    dns  = (v.get('DNSName','')  or '').split('.')[0].lower()
    if name == '${TARGET}'.lower() or dns == '${TARGET}'.lower():
        ips = v.get('TailscaleIPs',[])
        if ips: print(ips[0]); break
" 2>/dev/null || true)
    [ -n "$IP" ] && log "found $TARGET via tailscale status: $IP"
  fi
fi

if [ -z "$IP" ]; then
  log "ERROR: $TARGET not found on Tailnet. Is the sidecar running?"
  log "  Check: NOMAD_ADDR=http://100.75.75.39:4646 nomad job status windesk-tsnet-sidecar"
  exit 1
fi

# ── Send the message ───────────────────────────────────────────────────────────
URL="http://${IP}:${MESH_PORT}/msg"
PAYLOAD="{\"from\":\"$(hostname)\",\"body\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$MESSAGE")}"
log "POST $URL"
log "payload: $PAYLOAD"

HTTP=$(curl -sf -w "\n%{http_code}" -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  --max-time 10)

BODY=$(echo "$HTTP" | head -n -1)
CODE=$(echo "$HTTP" | tail -n 1)
if [ "$CODE" = "204" ] || [ "$CODE" = "200" ]; then
  echo "✓ message delivered to $TARGET ($IP:$MESH_PORT) — HTTP $CODE"
else
  echo "✗ delivery failed: HTTP $CODE"
  [ -n "$BODY" ] && echo "  body: $BODY"
  exit 1
fi
