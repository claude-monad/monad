#!/usr/bin/env bash
# build-image.sh — build the monad-agent-mesh image (run on a docker node, e.g. oraclebox1).
# Multi-stage: compiles the tsnet sidecar, then bundles claude + codex + the mesh tooling.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:-monad-agent-mesh}"
# Nomad's docker driver only uses REGISTRY images here, so we push to a node-local
# registry (oraclebox1:5000). AGENT_UID/GID match the host's ubuntu so mounted creds work.
REGISTRY="${REGISTRY:-localhost:5000}"
echo "[build-image] building $IMAGE from $HERE (arch: $(uname -m)) …"
sudo docker build --build-arg AGENT_UID="${AGENT_UID:-$(id -u)}" --build-arg AGENT_GID="${AGENT_GID:-$(id -g)}" -t "$IMAGE" "$HERE"
echo "[build-image] ensuring local registry at $REGISTRY …"
sudo docker run -d --restart=always -p 127.0.0.1:5000:5000 --name monad-registry registry:2 >/dev/null 2>&1 \
  || sudo docker start monad-registry >/dev/null 2>&1 || true
echo "[build-image] pushing $REGISTRY/$IMAGE:latest …"
sudo docker tag "$IMAGE:latest" "$REGISTRY/$IMAGE:latest"
sudo docker push "$REGISTRY/$IMAGE:latest"
echo "[build-image] done — job image: $REGISTRY/$IMAGE:latest"
