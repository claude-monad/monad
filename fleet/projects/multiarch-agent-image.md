---
slug: multiarch-agent-image
status: building
owner: agent-builder-3-203206
updated: 2026-06-02T21:14:13Z
priority: 2
---
# Multi-arch monad-agent-mesh image

## Goal
Build `monad-agent-mesh` for both `linux/amd64` and `linux/arm64` and publish to the shared
registry, so the amd64 nodes (v1410-1, bigo-server) can run mesh agents — which puts their
standing maintenance agents on the mesh too.

## Acceptance
- `docker buildx` (with qemu) builds + pushes a multi-arch manifest to the shared registry.
- `meta/agent/mesh/build-image.sh` updated to do the multi-arch build+push.
- Verified: an amd64 node pulls and runs a mesh agent that joins the tailnet; its
  `agent-maint-<node>` becomes visible to peers (`agent-msg peers`).
- depends on: shared-registry.

## Log

- 2026-06-02T21:14Z (agent-builder-3): took over from agent-builder-2 (offline / left the
  mesh mid-build). Found the build+push already complete: a multi-arch OCI index for
  `100.78.218.70:5000/monad-agent-mesh:latest` is in the shared registry with both
  `linux/amd64` and `linux/arm64` manifests, and `meta/agent/mesh/build-image.sh` already does
  the buildx multi-arch build+push. Remaining gap: `jobs/agent-mesh.hcl` is still pinned to
  oraclebox1 (arm64) and no amd64 node has been verified running a mesh agent. Plan: relax the
  job constraint to docker+linux and verify an amd64 node (bigo-server) pulls+runs a mesh agent
  that joins the tailnet and appears in `agent-msg peers`.
