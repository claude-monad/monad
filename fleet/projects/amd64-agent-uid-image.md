---
slug: amd64-agent-uid-image
status: done
owner: agent-builder-3-220238
updated: 2026-06-02T22:16:00Z
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
- 2026-06-02T22:16Z (agent-builder-3-220238) — **DONE.** Took over an orphaned claim
  (prev owner agent-builder-3-214229 left the mesh having only committed the claim, empty
  log). Found the full pipeline already wired by earlier #9 work: `Dockerfile` has
  `ARG AGENT_UID/AGENT_GID` (default 1001) and remaps the `ubuntu` user;
  `meta/agent/mesh/build-image.sh` forwards them as `--build-arg` and honours `TAG`;
  `jobs/agent-mesh-image-build.hcl` exposes `-meta uid/gid/tag`; `jobs/agent-mesh.hcl` pulls
  `…/monad-agent-mesh:uid${meta.agent_uid}`; and node meta is set (oraclebox1 `agent_uid=1001`,
  V1410-1 `agent_uid=1000`). The remaining gap was that the per-uid tags were unverified.
  **Verified all of it** on V1410-1 (amd64, docker driver) by pulling each tag from the shared
  registry `100.78.218.70:5000` and running `id ubuntu` (entrypoint overridden so no TS key
  needed):
    - `monad-agent-mesh:uid1000` → `uid=1000(ubuntu) gid=1000(ubuntu)` ✓ (so host `/home/e`
      mode-600 creds become readable on V1410-1 — the uid blocker is cleared)
    - `monad-agent-mesh:uid1001` → `uid=1001(ubuntu)` ✓
    - `monad-agent-mesh:latest`  → `uid=1001(ubuntu)` ✓ (oraclebox1 path NOT regressed;
      `latest` stays uid1001, and live mesh agents already run there)
  All three tags are multi-arch OCI indexes (`linux/amd64` + `linux/arm64`). Verification probe
  was a throwaway batch job, run directly and `-purge`d (no jobs/ or git pollution).
  **How to use:** to (re)build a per-uid variant, dispatch
  `nomad job dispatch -meta registry=100.78.218.70:5000 -meta uid=<N> -meta gid=<N> -meta tag=uid<N> agent-mesh-image-build`
  on bigo-server; consumers select it automatically via node meta `agent_uid`.
  **Note:** this clears blocker #2 of [[agent-mesh-cred-portability]] (#9). Full briefed-agent
  dispatch on V1410-1 still gates on blocker #1, [[amd64-agent-checkout-sync]] (#11, the
  wrong-origin host checkout), which needs owner approval for a destructive re-point — not this
  project's scope. Once #11 lands, flip the node on with
  `nomad node meta apply -node-id bf373a6f agent_mesh_ready=true`.
