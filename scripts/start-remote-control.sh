#!/usr/bin/env bash
# start-remote-control.sh — Launch a persistent Claude remote-control session for this node.
#
# Usage: start-remote-control.sh [--name <name>]
#
# Starts claude in remote-control mode, working in the monad repo. You can connect
# to it from claude.ai/code or the Claude mobile app.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NODE="$(hostname)"
NAME="${1:-}"
[ "$NAME" = "--name" ] && NAME="${2:-}"
[ -z "$NAME" ] && NAME="maint-${NODE}"

export NOMAD_ADDR="${NOMAD_ADDR:-http://100.75.75.39:4646}"

echo "[remote-control] Starting session '$NAME' on $NODE"
echo "[remote-control] Working directory: $REPO_DIR"
echo "[remote-control] Connect at: https://claude.ai/code"
echo ""

cd "$REPO_DIR"

# If running as root, drop to a credentialed user
if [ "$(id -u)" = "0" ]; then
    for u in e bigo ubuntu eliott; do
        if id "$u" &>/dev/null && su - "$u" -c "command -v claude >/dev/null 2>&1"; then
            echo "[remote-control] Dropping to user: $u"
            exec su - "$u" -c "cd '$REPO_DIR' && claude remote-control --name '$NAME' --permission-mode bypassPermissions --spawn same-dir"
        fi
    done
    echo "[remote-control] ERROR: no non-root user with claude found" >&2
    exit 1
fi

exec claude remote-control --name "$NAME" --permission-mode bypassPermissions --spawn same-dir
