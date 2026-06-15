#!/usr/bin/env bash
# codex-coordinator.sh — talk to the standing containerized Codex coordinator on the mesh.
#
# Usage:
#   codex-coordinator.sh ask "what changed?"
#   codex-coordinator.sh ask --agent agent-cluster-coordinator "restart the sync job"
#   codex-coordinator.sh peers
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_MSG="$HERE/../meta/agent/mesh/agent-msg.sh"
CMD="${1:-ask}"
shift || true

TARGET="agent-cluster-coordinator"
WAIT="${COORD_WAIT:-90}"
export MESH_RELAY="${MESH_RELAY:-http://100.75.75.39:8477}"
export AGENT_NAME="${AGENT_NAME:-operator-$(hostname -s 2>/dev/null || hostname)-$$}"

die() { echo "codex-coordinator: $*" >&2; exit 2; }

recv_reply() {
  python3 - "$TARGET" <<'PY'
import json, sys
target = sys.argv[1]
try:
    msgs = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for m in msgs:
    if m.get("from") == target:
        print(m.get("body", ""))
        sys.exit(0)
PY
}

case "$CMD" in
  ask)
    if [ "${1:-}" = "--agent" ]; then
      TARGET="${2:-}"
      shift 2
    fi
    [ $# -gt 0 ] || die "usage: ask [--agent name] <message>"
    MSG="$*"
    bash "$AGENT_MSG" register >/dev/null
    bash "$AGENT_MSG" send "$TARGET" "$MSG" >/dev/null
    deadline=$(( $(date +%s) + WAIT ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
      out="$(bash "$AGENT_MSG" recv --wait 10)"
      reply="$(printf '%s' "$out" | recv_reply || true)"
      if [ -n "${reply:-}" ]; then
        printf '%s\n' "$reply"
        exit 0
      fi
    done
    echo "codex-coordinator: timed out waiting for reply from $TARGET" >&2
    exit 1
    ;;
  peers)
    bash "$AGENT_MSG" peers
    ;;
  *)
    die "usage: {ask [--agent name] <message>|peers}"
    ;;
esac
