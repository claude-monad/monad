#!/usr/bin/env bash
# mesh-attach.sh — ensure THIS host runs a tsnet sidecar so its agent is a reachable mesh
# peer (agent-<name>). Builds the sidecar for this arch on demand (via a golang container,
# cached) and starts it. Idempotent and non-fatal: if it can't attach (no docker, no
# authkey), it just prints nothing and exits 1 — the caller stays usable, just off-mesh.
#
# Usage: mesh-attach.sh <agent-name> [local-port]
# On success prints the local API port (so the caller can `export LOCAL_PORT=<that>`).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # meta/agent/mesh
NAME="${1:-agent-$(hostname)}"
LOCAL_PORT="${2:-${MESH_LOCAL_PORT:-8473}}"
MESH_PORT="${MESH_PORT:-8472}"
BIN="$HERE/sidecar/tsnet-sidecar"
STATE="${TS_STATE_DIR:-/tmp/tsnet-$NAME}"
export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"

log() { echo "[mesh-attach] $*" >&2; }
# Record the live mesh port so any agent on this node can find the sidecar without env
# propagation (agent-msg reads this when LOCAL_PORT is unset).
state_write() { printf 'LOCAL_PORT=%s\nMESH_NAME=%s\n' "$LOCAL_PORT" "$NAME" > /tmp/monad-mesh.env 2>/dev/null || true; }

case "$(uname -m)" in
  x86_64|amd64)   ARCH=amd64 ;;
  aarch64|arm64)  ARCH=arm64 ;;
  *)              ARCH="$(uname -m)" ;;
esac
SHARED_BIN="/mnt/deathstar/bin/tsnet-sidecar-$ARCH"

# Already attached?
if curl -sf --max-time 3 "http://127.0.0.1:$LOCAL_PORT/whoami" >/dev/null 2>&1; then
  state_write; echo "$LOCAL_PORT"; exit 0
fi

# Pick a docker invocation that works (some nodes need sudo).
DK="docker"; docker info >/dev/null 2>&1 || DK="sudo docker"

nomad_registry() {
  command -v nomad >/dev/null 2>&1 || return 1
  for key in address addr registry value; do
    value="$(nomad var get -item="$key" infra/registry 2>/dev/null || true)"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

# Ensure the sidecar binary for this arch (cache once). PREFER the prebuilt binary on the
# shared storage (/mnt/deathstar/bin, NFS-mounted on every node) — no docker/registry/compile.
if [ ! -x "$BIN" ] && [ -x "$SHARED_BIN" ]; then
  if cp -f "$SHARED_BIN" "$BIN" 2>/dev/null && chmod +x "$BIN" 2>/dev/null; then
    log "got sidecar from shared storage ($ARCH)"
  fi
fi
# Fallbacks: extract from the agent image, else compile via golang.
if [ ! -x "$BIN" ]; then
  if [ -n "${MESH_IMAGE:-}" ]; then
    IMG="$MESH_IMAGE"
  else
    REGISTRY="${REGISTRY:-$(nomad_registry || true)}"
    IMG="${REGISTRY:-localhost:5000}/monad-agent-mesh:latest"
  fi
  cid="$($DK create "$IMG" 2>/dev/null || $DK create monad-agent-mesh:latest 2>/dev/null)"
  if [ -n "$cid" ] && $DK cp "$cid:/usr/local/bin/tsnet-sidecar" "$BIN" >/dev/null 2>&1; then
    chmod +x "$BIN"; $DK rm "$cid" >/dev/null 2>&1
    log "extracted sidecar from image for $(uname -m)"
  else
    [ -n "$cid" ] && $DK rm "$cid" >/dev/null 2>&1
    log "compiling tsnet sidecar for $(uname -m) (one-time, ~2-3 min)…"
    $DK run --rm -v "$HERE/sidecar":/src -w /src -e CGO_ENABLED=0 -e GOFLAGS=-buildvcs=false golang:1.23 \
      sh -c "go build -trimpath -ldflags='-s -w' -o tsnet-sidecar ." >/dev/null 2>&1 \
      || { log "sidecar build failed — node stays off-mesh"; exit 1; }
  fi
fi

AUTHKEY="$(nomad var get -item=tailscale_authkey secret/agent-mesh 2>/dev/null)"
[ -z "$AUTHKEY" ] && { log "no secret/agent-mesh authkey — not attaching"; exit 1; }

AGENT_NAME="$NAME" TS_AUTHKEY="$AUTHKEY" TS_STATE_DIR="$STATE" \
  LOCAL_PORT="$LOCAL_PORT" MESH_PORT="$MESH_PORT" \
  nohup "$BIN" >"/tmp/mesh-$NAME.log" 2>&1 &

for _ in $(seq 1 30); do
  curl -sf --max-time 2 "http://127.0.0.1:$LOCAL_PORT/whoami" >/dev/null 2>&1 && { state_write; echo "$LOCAL_PORT"; exit 0; }
  sleep 1
done
# Didn't come up — likely a wrong-arch binary (e.g. arm64 image extracted on amd64 before
# multi-arch images exist). Drop the cache so a later attach re-acquires the right one.
log "sidecar did not come up (see /tmp/mesh-$NAME.log) — clearing cached binary"
rm -f "$BIN"; exit 1
