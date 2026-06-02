---
slug: bigo-server-registry-trust
status: done
owner: agent-builder-3-211218
updated: 2026-06-02T21:31:00Z
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
- **2026-06-02 (builder-3-211218): DONE.** Ran `scripts/ensure-registry-trust.sh
  100.78.218.70:5000` on bigo-server via a raw_exec batch job (`jobs/registry-trust-bigo.hcl`,
  constrained to `${node.unique.name} = bigo-server`; script fetched from GitHub raw via an
  `artifact` stanza since bigo-server has no standard monad checkout). The script added the
  address to `/etc/docker/daemon.json` `insecure-registries` and SIGHUP-reloaded dockerd (no
  container restart). **Verified** on bigo-server: `daemon.json` now contains
  `{"insecure-registries":["100.78.218.70:5000"]}`, and `docker pull
  100.78.218.70:5000/monad-agent-mesh:latest` succeeds (EXIT=0, "Image is up to date").
  - **How to re-apply / where:** the fix is idempotent and node-doctor re-runs
    `ensure-registry-trust.sh` every pass, so trust persists. To re-verify manually, re-run
    `monad deploy jobs/registry-trust-bigo.hcl` (one-shot batch on bigo-server).
  - **Unblocks** [[amd64-maintenance-mesh]] (#7): bigo-server can now pull the shared
    `monad-agent-mesh` image, so its maintenance agent can extract the tsnet-sidecar.
</content>
