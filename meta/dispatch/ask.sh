#!/usr/bin/env bash
# ask.sh — fire ONE lightweight, TARGETED containerized Claude session at a
# specific question you supply (bypasses the frontier; no warm-up). This is the
# operator-driven form of the "targeted" job type.
#
# Usage:  ask.sh "your specific question or task"  [--detach]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
Q="${1:?usage: ask.sh \"specific question/task\" [--detach]}"
DETACH="${2:-}"

ACCOUNT="${MONAD_ACCOUNT:-$(grep -oP 'claude_account\s*=\s*"\K[^"]+' /etc/nomad.d/nomad.hcl 2>/dev/null | head -1)}"
ACCOUNT="${ACCOUNT:-pro}"

# one session per account at a time (shared credentials)
if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "session-container-${ACCOUNT}"; then
  echo "[ask] a '${ACCOUNT}' session is already running — wait, or stop it first." >&2
  exit 1
fi

PROMPT="$(cat "$HERE/../../scripts/prompts/targeted.md")
$Q
"
MID="container-${ACCOUNT}-ask-$(date +%s)"
echo "[ask] launching targeted session ($ACCOUNT) for: $Q"
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-1200}" exec bash "$HERE/run-container-session.sh" "$MID" "$PROMPT" $DETACH
