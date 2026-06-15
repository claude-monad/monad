#!/usr/bin/env bash
# codex-coordinator.sh — talk to the standing containerized Codex coordinator over HTTP.
#
# Usage:
#   codex-coordinator.sh ask "what changed?"
#   codex-coordinator.sh ask --url http://100.75.75.39:8310 "restart the sync job"
#   codex-coordinator.sh health
set -euo pipefail

CMD="${1:-ask}"
shift || true

URL="${CODEX_COORD_URL:-}"

die() { echo "codex-coordinator: $*" >&2; exit 2; }

resolve_url() {
  [ -n "$URL" ] && { printf '%s\n' "$URL"; return; }
  if command -v /home/claude/bin/nomad >/dev/null 2>&1; then
    python3 - <<'PY'
import json, os, subprocess, sys
env = dict(os.environ)
env.setdefault("NOMAD_ADDR", "http://100.75.75.39:4646")
svc_out = subprocess.check_output(
    ["/home/claude/bin/nomad", "service", "info", "-json", "codex-cluster-coordinator"],
    env=env,
    text=True,
)
svc = json.loads(svc_out)
if not svc:
    raise SystemExit(1)
node_id = svc[0]["NodeID"]
port = svc[0]["Port"]
node_out = subprocess.check_output(
    ["/home/claude/bin/nomad", "node", "status", "-json", node_id],
    env=env,
    text=True,
)
node = json.loads(node_out)
advertise = (node.get("Attributes", {}) or {}).get("unique.advertise.address", "")
host = advertise.split(":", 1)[0] if advertise else svc[0]["Address"]
print(f"http://{host}:{port}")
PY
    return
  fi
  printf '%s\n' "http://100.78.218.70:8310"
}

http_get() {
  python3 - "$1" <<'PY'
import sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=20) as r:
    sys.stdout.write(r.read().decode())
PY
}

http_post() {
  python3 - "$1" "$2" <<'PY'
import json, sys, urllib.request
url, text = sys.argv[1], sys.argv[2]
body = json.dumps({"text": text}).encode()
req = urllib.request.Request(url, data=body, method="POST", headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=900) as r:
    sys.stdout.write(r.read().decode())
PY
}

case "$CMD" in
  ask)
    if [ "${1:-}" = "--url" ]; then
      URL="${2:-}"
      shift 2
    fi
    [ $# -gt 0 ] || die "usage: ask [--url coordinator-url] <message>"
    URL="$(resolve_url)"
    http_post "$URL/ask" "$*"
    ;;
  health)
    URL="$(resolve_url)"
    http_get "$URL/health"
    ;;
  *)
    die "usage: {ask [--url coordinator-url] <message>|health}"
    ;;
esac
