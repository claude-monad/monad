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

URL="${CODEX_COORD_URL:-http://100.75.75.39:8310}"

die() { echo "codex-coordinator: $*" >&2; exit 2; }

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
    http_post "$URL/ask" "$*"
    ;;
  health)
    http_get "$URL/health"
    ;;
  *)
    die "usage: {ask [--url coordinator-url] <message>|health}"
    ;;
esac
