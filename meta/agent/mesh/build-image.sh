#!/usr/bin/env bash
# build-image.sh — build the monad-agent-mesh image (run on a docker node, e.g. oraclebox1).
# Multi-stage: compiles the tsnet sidecar, then bundles claude + codex + the mesh tooling.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:-monad-agent-mesh}"
TAG="${TAG:-latest}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${BUILDER:-monad-agent-mesh-multiarch}"
AGENT_UID="${AGENT_UID:-1001}"
AGENT_GID="${AGENT_GID:-1001}"

nomad_registry() {
  command -v nomad >/dev/null 2>&1 || return 1
  for key in address addr registry value; do
    value="$(nomad var get -item="$key" infra/registry 2>/dev/null || true)"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

REGISTRY="${REGISTRY:-$(nomad_registry || true)}"
# Keep the current node-local path working until the shared registry is deployed.
REGISTRY="${REGISTRY:-localhost:5000}"
IMAGE_REF="${REGISTRY%/}/$IMAGE:$TAG"

docker_cmd=(docker)
if ! "${docker_cmd[@]}" info >/dev/null 2>&1; then
  docker_cmd=(sudo docker)
fi
if ! "${docker_cmd[@]}" info >/dev/null 2>&1; then
  echo "[build-image] docker is not available; run on a Nomad node with docker" >&2
  exit 1
fi

echo "[build-image] image=$IMAGE_REF platforms=$PLATFORMS uid=$AGENT_UID gid=$AGENT_GID"

if [ "$REGISTRY" = "localhost:5000" ] || [ "$REGISTRY" = "127.0.0.1:5000" ]; then
  echo "[build-image] ensuring fallback local registry at $REGISTRY"
  "${docker_cmd[@]}" run -d --restart=always -p 127.0.0.1:5000:5000 --name monad-registry registry:2 >/dev/null 2>&1 \
    || "${docker_cmd[@]}" start monad-registry >/dev/null 2>&1 || true
fi

if ! "${docker_cmd[@]}" buildx version >/dev/null 2>&1; then
  echo "[build-image] docker buildx is required for multi-arch builds" >&2
  exit 1
fi

if [ "${INSTALL_BINFMT:-1}" != "0" ]; then
  echo "[build-image] ensuring binfmt handlers for cross-arch builds"
  "${docker_cmd[@]}" run --privileged --rm tonistiigi/binfmt --install arm64,amd64 >/dev/null
fi

if ! "${docker_cmd[@]}" buildx inspect "$BUILDER" >/dev/null 2>&1; then
  # Host networking lets buildkit push to the fallback localhost registry.
  "${docker_cmd[@]}" buildx create --name "$BUILDER" --driver docker-container --driver-opt network=host --use >/dev/null
else
  "${docker_cmd[@]}" buildx use "$BUILDER" >/dev/null
fi
"${docker_cmd[@]}" buildx inspect --bootstrap "$BUILDER" >/dev/null

echo "[build-image] building and pushing $IMAGE_REF from $HERE"
"${docker_cmd[@]}" buildx build \
  --builder "$BUILDER" \
  --platform "$PLATFORMS" \
  --build-arg "AGENT_UID=$AGENT_UID" \
  --build-arg "AGENT_GID=$AGENT_GID" \
  -t "$IMAGE_REF" \
  --push \
  "$HERE"

echo "[build-image] done: $IMAGE_REF"
