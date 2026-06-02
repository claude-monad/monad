#!/usr/bin/env bash
# ensure-registry-trust.sh — make this node's docker daemon trust the shared cluster
# registry as an insecure registry, so `docker pull <addr>/<img>` works over the
# tailnet (the registry is plain HTTP on the tailnet, no TLS).
#
# Idempotent and cron-safe: node-doctor calls this every pass. It edits
# /etc/docker/daemon.json's "insecure-registries" list and restarts docker ONLY if
# the address was actually missing. Non-fatal by design — a node without docker, or
# where we can't get root, just logs a warning and moves on.
#
# Address resolution order: $1 arg → $REGISTRY_ADDR env → Nomad var infra/registry
# (key "addr") → built-in default. Keep the default in sync with jobs/registry.hcl.
set -uo pipefail

DEFAULT_ADDR="100.78.218.70:5000"

log()  { printf '\033[0;36m[registry-trust]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[registry-trust]\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""; [ "$(id -u)" -ne 0 ] && have sudo && SUDO="sudo"

# --- resolve the registry address ---------------------------------------------
ADDR="${1:-${REGISTRY_ADDR:-}}"
if [ -z "$ADDR" ] && have nomad; then
  ADDR="$(nomad var get -out json infra/registry 2>/dev/null \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["Items"].get("addr",""))' 2>/dev/null || true)"
fi
ADDR="${ADDR:-$DEFAULT_ADDR}"

# --- nothing to do without docker ---------------------------------------------
if ! have docker; then
  log "no docker on this node — skipping (nothing to trust)"
  exit 0
fi
if ! have python3; then
  warn "python3 required to edit daemon.json safely — skipping"
  exit 0
fi

DAEMON_JSON="/etc/docker/daemon.json"

# --- already trusted? bail fast (no sudo, no restart) -------------------------
if [ -f "$DAEMON_JSON" ] && python3 - "$DAEMON_JSON" "$ADDR" <<'PY' 2>/dev/null
import sys, json
path, addr = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path))
except Exception:
    sys.exit(1)
sys.exit(0 if addr in (d.get("insecure-registries") or []) else 1)
PY
then
  log "docker already trusts $ADDR — ok"
  exit 0
fi

# --- merge the address in (atomic write via temp file) ------------------------
log "adding $ADDR to docker insecure-registries…"
TMP="$(mktemp)"
if ! python3 - "$DAEMON_JSON" "$ADDR" > "$TMP" <<'PY'
import sys, json, os
path, addr = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(path):
    try:
        d = json.load(open(path)) or {}
    except Exception:
        d = {}
lst = d.get("insecure-registries") or []
if addr not in lst:
    lst.append(addr)
d["insecure-registries"] = lst
print(json.dumps(d, indent=2))
PY
then
  warn "failed to render new daemon.json — leaving config untouched"
  rm -f "$TMP"
  exit 0
fi

$SUDO mkdir -p /etc/docker
$SUDO cp "$TMP" "$DAEMON_JSON"
rm -f "$TMP"

# --- reload docker to pick up the change --------------------------------------
# `insecure-registries` is a live-reloadable daemon option, so we send SIGHUP
# (systemctl reload / kill -HUP) instead of a full restart. This applies the trust
# WITHOUT bouncing running containers — critical on nodes hosting mesh agents whose
# jobs don't auto-restart.
if have systemctl; then
  log "reloading docker (SIGHUP, no container restart)…"
  $SUDO systemctl reload docker 2>/dev/null \
    || warn "docker reload failed — run '$SUDO systemctl reload docker' manually"
elif have pidof; then
  log "reloading docker (kill -HUP dockerd)…"
  $SUDO kill -HUP "$(pidof dockerd)" 2>/dev/null \
    || warn "could not signal dockerd — reload it manually to apply: $ADDR"
else
  warn "no systemctl/pidof — reload docker manually to apply: $ADDR"
fi

log "done — $ADDR is now a trusted insecure registry"
