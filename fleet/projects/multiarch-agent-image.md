---
slug: multiarch-agent-image
status: todo
owner: ""
updated: ""
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
