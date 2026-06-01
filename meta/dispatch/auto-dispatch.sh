#!/usr/bin/env bash
# auto-dispatch.sh — autonomously keep ONE containerized research session running
# on THIS host, chosen + deduped by the frontier dispatcher. Designed for cron or
# a loop; the running-container guard prevents stacking sessions on the one set of
# account credentials (which also keeps rate-limit usage sane).
#
#   Account is detected from the Nomad client config (meta.claude_account), else
#   $MONAD_ACCOUNT, else "pro".
#
# Job type (mode): arg $1 or $MONAD_MODE, default "explorer" (deep, bread-and-
# butter). Use "targeted" for fast, single-question sessions.
#
# Cron example (deep explorer every 15 min):
#   */15 * * * * /home/ubuntu/monad/meta/dispatch/auto-dispatch.sh >> /tmp/auto-dispatch.log 2>&1
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="${1:-${MONAD_MODE:-explorer}}"
ACCOUNT="${MONAD_ACCOUNT:-}"
if [ -z "$ACCOUNT" ]; then
  ACCOUNT="$(grep -oP 'claude_account\s*=\s*"\K[^"]+' /etc/nomad.d/nomad.hcl 2>/dev/null | head -1)"
fi
ACCOUNT="${ACCOUNT:-pro}"

# one session per account at a time (shared credentials + rate limits)
if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "session-container-${ACCOUNT}"; then
  echo "[auto-dispatch] $(date -Is): a '${ACCOUNT}' session is already running — skipping."
  exit 0
fi

# preflight: image + auth present
if ! sudo docker image inspect "${MONAD_SESSION_IMAGE:-monad-claude-session}" >/dev/null 2>&1; then
  echo "[auto-dispatch] image missing — run meta/dispatch/build-image.sh"; exit 1
fi
[ -f "$HOME/.claude/.credentials.json" ] || { echo "[auto-dispatch] no Claude login on host"; exit 1; }

echo "[auto-dispatch] $(date -Is): dispatching one '${MODE}' container for account '${ACCOUNT}'"
cd "$HERE/../coordination"
exec python3 dispatcher.py --exec container --commit --account "$ACCOUNT" --mode "$MODE" --max-dispatch 1
