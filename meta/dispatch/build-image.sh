#!/usr/bin/env bash
# build-image.sh — build the monad-claude-session container image used by the
# container execution backend of the dispatcher.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${MONAD_SESSION_IMAGE:-monad-claude-session}"
echo "[build-image] building $IMAGE from $HERE ..."
sudo docker build -t "$IMAGE" "$HERE"
echo "[build-image] done. Test auth with:"
echo "  meta/dispatch/auth-check.sh"
