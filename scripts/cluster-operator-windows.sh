#!/bin/bash
# cluster-operator-windows.sh — persistent remote-control session (Windows/git-bash)
set -uo pipefail

MONAD_DIR="${MONAD_REPO_DIR:-C:/Users/Eliott/monad}"
SESSION_NAME="${OPERATOR_NAME:-monad-operator}"

cd "$MONAD_DIR" || { echo "ERROR: monad repo not at $MONAD_DIR"; exit 1; }
git pull --ff-only 2>/dev/null || true

echo "[cluster-operator] $(date -Is): starting remote-control session '$SESSION_NAME'"
echo "[cluster-operator] working directory: $MONAD_DIR"

exec claude remote-control --name "$SESSION_NAME" --spawn same-dir --verbose
