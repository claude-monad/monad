#!/usr/bin/env bash
# build-image.sh — build the monad-agent-mesh image (run on a docker node, e.g. oraclebox1).
# Multi-stage: compiles the tsnet sidecar, then bundles claude + codex + the mesh tooling.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:-monad-agent-mesh}"
echo "[build-image] building $IMAGE from $HERE (arch: $(uname -m)) …"
exec sudo docker build -t "$IMAGE" "$HERE"
