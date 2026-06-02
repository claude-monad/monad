---
slug: amd64-agent-uid-image
status: building
owner: agent-builder-3-220238
updated: 2026-06-02T22:13:00Z
priority: 12
---
# Per-host uid variants of the agent-mesh image

## Goal
Clear the second blocker from [[agent-mesh-cred-portability]]: the `monad-agent-mesh` image
runs `ubuntu` as **uid 1001** (oraclebox1's), but the amd64 nodes' credentialed users have
different uids (V1410-1's `e` = **1000**; bigo-server's `bigo` = TBD). Mode-600 Claude/codex
creds bind-mounted from the host are unreadable across a uid boundary, so a briefed agent on
V1410-1 can't read its creds even once the repo checkout is fixed (that's [[amd64-agent-checkout-sync]]).

Produce **per-uid image variants** (the Dockerfile already supports `--build-arg AGENT_UID/AGENT_GID`)
and have `jobs/agent-mesh.hcl` select the right one per node via a `meta.agent_uid` node attribute.

## Why
Independent of the host-checkout sync ([[amd64-agent-checkout-sync]], blocker #1): this builds
from `origin/main` in a worktree on bigo-server, so it does not assume host repos are synced.
Together the two unblock briefed mesh agents on amd64 (the remaining work in
[[agent-mesh-cred-portability]]).

## Placement
Build runs on **bigo-server** (the registry + docker + buildx host; `agent-mesh-image-build`
is already constrained there). Cross-uid is just a build-arg, so all uid variants build on that
one node. The resulting images are consumed by `agent-mesh` on whichever node has
`agent_mesh_ready=true`, selected by `meta.agent_uid`.

## Acceptance
- `jobs/agent-mesh-image-build.hcl` accepts `uid`/`gid` dispatch meta (default 1001) and passes
  them to `build-image.sh` → `--build-arg AGENT_UID/AGENT_GID`. Default behavior (no meta) is
  unchanged (still uid 1001).
- The shared registry (`100.78.218.70:5000`) holds per-uid tags of `monad-agent-mesh`:
  at least `uid1001` (oraclebox1) and `uid1000` (V1410-1). `latest` stays = uid1001 so existing
  consumers (`mesh-attach.sh`, `fleet-builder.hcl`) don't break.
- `jobs/agent-mesh.hcl` pulls `…/monad-agent-mesh:uid${meta.agent_uid}`; node meta `agent_uid`
  is set on oraclebox1=1001 and V1410-1=1000 (and bigo once known). The oraclebox1 path is NOT
  regressed (a dispatch still lands + runs healthy there).
- Verified: the `uid1000` image, run on V1410-1, reports `id -u ubuntu = 1000` (so host
  `/home/e` mode-600 creds become readable). [Full briefed-dispatch verification stays gated on
  [[amd64-agent-checkout-sync]] + creds — note it, don't block on it.]

## Log
