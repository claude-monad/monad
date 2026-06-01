#!/bin/bash
# ensure-operator.sh — keepalive for the monad-operator session on Windows
# Run from a scheduled task every 5 minutes. Starts the operator if not running.
set -uo pipefail

LOCKFILE="/tmp/monad-operator.lock"
LOGFILE="/tmp/cluster-operator.log"

# Check if operator is already running
if [ -f "$LOCKFILE" ]; then
  PID=$(cat "$LOCKFILE" 2>/dev/null)
  if kill -0 "$PID" 2>/dev/null; then
    exit 0  # already running
  fi
  rm -f "$LOCKFILE"
fi

# Start operator
cd C:/Users/Eliott/monad
nohup claude remote-control --name "monad-operator" --spawn same-dir >> "$LOGFILE" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$LOCKFILE"
echo "[ensure-operator] $(date -Is): started monad-operator (PID $NEW_PID)"
