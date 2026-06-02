---
slug: agent-mesh-alloc-clone
status: building
owner: agent-builder-3-221913
updated: 2026-06-02T22:30:00Z
priority: 15
---
# agent-mesh: fresh per-alloc repo clone (drop the host-checkout mount)

## Goal
Let briefed `agent-mesh` agents run healthy on amd64 nodes (V1410-1, bigo-server) **without**
the destructive host-checkout fix that blocks [[amd64-agent-checkout-sync]] (#11) and
[[agent-mesh-cred-portability]] (#9 blocker #1). Make `jobs/agent-mesh.hcl` clone a fresh,
correct-origin repo into the alloc-local `/work` (exactly like `jobs/fleet-builder.hcl` already
does) instead of bind-mounting `${meta.agent_home}/monad`.

## Why
The keystone blocker (#11) is that V1410-1's `/home/e/monad` and bigo-server's `/home/bigo/monad`
track the WRONG git remote (`eliottcassidy2000/monad@4f6a4dc`) and are missing
`meta/agent/run-agent.sh` etc. Mounting them at `/work` makes briefed agents die `exit 127`.
A `git pull --ff-only` can never reach current code (no fast-forward path between lineages), so
the only host-checkout fix is a destructive re-point+reset that needs owner approval.

But the host checkout is only used to supply *repo code* at `/work`. `fleet-builder.hcl` already
sidesteps this for builders by cloning a fresh `eliott-monad/monad` into a container-local
`/work` at start. Applying the same pattern to `agent-mesh.hcl` makes briefed mesh agents get
correct code on ANY node regardless of host-checkout state — no owner decision, nothing
destructive, nothing on the hosts touched. The conductor's #11 escalation explicitly names this
"non-destructive fresh-per-alloc-clone redesign of agent-mesh, like fleet-builder" as the
alternative path. uid-matched creds (blocker #2) are already solved by [[amd64-agent-uid-image]].

## Placement
No new infra. Edit `jobs/agent-mesh.hcl` only. Verify first on oraclebox1 (already
`agent_mesh_ready=true`, reachable) so the working path is not regressed, then flip
`agent_mesh_ready=true` on V1410-1 (`agent_home=/home/e`, `agent_uid=1000` already wired) and
verify a briefed dispatch lands + runs healthy there.

## Acceptance
- `jobs/agent-mesh.hcl` no longer bind-mounts `${meta.agent_home}/monad:/work`; instead an
  entrypoint override clones `https://github.com/eliott-monad/monad` into `/work` if
  `/work/.git` is absent, then execs the image's normal `agent-entrypoint` (mirrors
  `fleet-builder.hcl`). Cred mounts (`.claude`, `.claude.json`, `.codex`) are unchanged.
- `monad validate` passes; redeploy is healthy on oraclebox1 (no regression: a briefed dispatch
  there still runs).
- V1410-1 flipped `agent_mesh_ready=true`; a briefed `agent-mesh` dispatch (e.g. a short
  "report your hostname + that /work has meta/agent/run-agent.sh, then idle") lands on V1410-1
  and runs healthy (no `exit 127`), proving correct repo code + readable creds on an amd64 node.
- Unblocks #9's acceptance item 3 and removes the need for #11's destructive step for mesh work.

## Log
- 2026-06-02 (agent-builder-3-221913) claimed. Non-destructive alternative to #11, blessed by
  the conductor's escalation event. Building now.
