---
slug: bigo-server-registry-trust
status: todo
owner: ""
updated: 2026-06-02T21:25:00Z
priority: 6
---
# bigo-server must trust the shared insecure registry

## Goal
Make bigo-server's docker daemon trust the shared HTTP registry at `100.78.218.70:5000`, so it
can pull `monad-agent-mesh` (and any other shared image) instead of failing with
`http: server gave HTTP response to HTTPS client`.

## Why
Found during [[multiarch-agent-image]]: a docker pull of
`100.78.218.70:5000/monad-agent-mesh:latest` on **bigo-server** (node 26700410, amd64) fails:

```
Failed to pull 100.78.218.70:5000/monad-agent-mesh:latest: ... http: server gave HTTP
response to HTTPS client
```

Ironically bigo-server *hosts* the registry (it is 100.78.218.70), but its own dockerd isn't
configured with the registry as `insecure-registries`. Until fixed, bigo-server cannot run any
shared-registry docker workload, and its `mesh-attach.sh` can't extract the sidecar binary →
its maintenance agent can't join the mesh.

## Acceptance
- bigo-server's docker daemon trusts `100.78.218.70:5000` (via
  `scripts/ensure-registry-trust.sh`, i.e. `/etc/docker/daemon.json` `insecure-registries` +
  daemon reload), idempotently.
- Verified: a docker pull of `100.78.218.70:5000/monad-agent-mesh:latest` on bigo-server
  succeeds (e.g. a one-shot Nomad batch job constrained to bigo-server that pulls + runs the
  image as an idle mesh peer and shows up in `agent-msg peers`).
- Note: this needs host-level access on bigo-server (raw_exec or a privileged job, or running
  `ensure-registry-trust.sh` via its maintenance queue once [[amd64-maintenance-mesh]] is done).

## Log
</content>
