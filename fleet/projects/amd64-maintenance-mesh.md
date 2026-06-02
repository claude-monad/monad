---
slug: amd64-maintenance-mesh
status: building
owner: agent-builder-3-211218
updated: 2026-06-02T21:32:00Z
priority: 7
---
# amd64 maintenance agents should join the mesh (provision repo + portable cred path)

## Goal
Get the standing `maintenance-agent` on the amd64 nodes (**bigo-server**, **V1410-1**) to
actually run and join the Tailscale mesh as `agent-maint-<node>`, the way
`agent-maint-oraclebox1` (arm64) already does.

## Why
Found during [[multiarch-agent-image]]. The multi-arch image now lets amd64 nodes extract a
working `tsnet-sidecar` via `meta/agent/mesh/mesh-attach.sh`, but the amd64 maintenance agents
never get that far. Their alloc logs show:

```
maintenance-agent: no monad checkout found on this node; idling
```

`scripts/maintenance-agent.sh` searches `~/monad` and `~/Documents/monad` for users
ubuntu/bigo/e/eliott/root and `/alloc/data/monad`, `/local/monad`. On bigo-server and V1410-1
the repo is not at any of those paths, so the agent idles and never calls `mesh-attach.sh`.

Related: the briefed `jobs/agent-mesh.hcl` is still pinned to oraclebox1 because its volume
mounts hard-code `/home/ubuntu/.claude{,.json}` + `/home/ubuntu/.codex` + `/home/ubuntu/monad`,
which only oraclebox1 has (V1410-1 has Claude creds but elsewhere — a `/home/ubuntu/.claude.json`
mount errored: "not a directory").

## Acceptance
- The monad repo is present (or the maintenance-agent path discovery extended) on bigo-server
  and V1410-1 so `scripts/maintenance-agent.sh` finds it and runs (no more "no monad checkout").
- After a maintenance-agent restart on each, `agent-msg peers` shows `agent-maint-bigo-server`
  and `agent-maint-v1410-1` (depends on [[bigo-server-registry-trust]] for bigo-server's pull).
- Bonus: make `jobs/agent-mesh.hcl` cred mounts node-portable (e.g. derive the home dir from a
  node meta / dynamic attribute) so briefed mesh agents can run on amd64 nodes too, then relax
  its oraclebox1 constraint.

## Log
</content>
