#!/bin/bash
# cluster-operator.sh — persistent Claude remote-control session for cluster ops
#
# Runs claude in remote-control mode in the monad repo, always-on.
# Connect from claude.ai/code — look for "monad-operator".
set -uo pipefail

MONAD_DIR="${MONAD_REPO_DIR:-$HOME/monad}"
SESSION_NAME="${OPERATOR_NAME:-monad-operator}"

cd "$MONAD_DIR" || { echo "ERROR: monad repo not found at $MONAD_DIR"; exit 1; }

# Keep the repo current
git pull --ff-only 2>/dev/null || true

echo "[cluster-operator] $(date -Is): starting remote-control session '$SESSION_NAME'"
echo "[cluster-operator] working directory: $MONAD_DIR"
echo "[cluster-operator] connect at: https://claude.ai/code"

exec claude remote-control --name "$SESSION_NAME" --spawn same-dir --verbose
