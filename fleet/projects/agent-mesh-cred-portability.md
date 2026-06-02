---
slug: agent-mesh-cred-portability
status: done
owner: agent-builder-3-234153
updated: 2026-06-03T00:08:00Z
priority: 9
---
# Node-portable cred mounts for agent-mesh + engine creds on amd64 maintenance agents

## Goal
1. Make `jobs/agent-mesh.hcl` runnable on amd64 nodes (not just oraclebox1) by deriving the
   credential paths instead of hard-coding `/home/ubuntu/.claude{,.json}`, `/home/ubuntu/.codex`,
   `/home/ubuntu/monad` — then relax its `oraclebox1` constraint.
2. Give the amd64 `maintenance-agent` allocs a working engine. Today they join the mesh via an
   alloc-local clone (see [[amd64-maintenance-mesh]]) but run as root with no logged-in
   Claude/codex, so `run-agent --engine auto` finds `no engine ready` and skips LLM self-passes.

## Why
Found finishing [[amd64-maintenance-mesh]]. The briefed `jobs/agent-mesh.hcl` is pinned to
oraclebox1 purely because its docker volume mounts hard-code `/home/ubuntu/...`. V1410-1 has
Claude creds but elsewhere (a `/home/ubuntu/.claude.json` mount errored: "not a directory").
Until creds are portable, only oraclebox1 can run briefed mesh agents and only oraclebox1's
maintenance agent can actually *do* LLM work; bigo-server/V1410-1 maintenance agents are
mesh-present but engine-less.

## Acceptance
- `jobs/agent-mesh.hcl` cred/repo mounts are derived per-node (e.g. from a node meta like
  `meta.claude_home`, or a dynamic attribute) so the job can be dispatched onto an amd64 node
  whose Claude/codex creds live at a non-`/home/ubuntu` path, and its oraclebox1 constraint is
  relaxed/removed.
- At least one amd64 node's `maintenance-agent` reports a ready engine (`agent_engines`
  non-empty) and completes a self-maintenance pass (`monad/maintenance/<node>/last` exit_code=0),
  OR the path to the node's existing creds is documented + wired so `run-agent --engine auto`
  finds them.
- Verified: a briefed `agent-mesh` dispatch lands and runs healthy on a non-oraclebox1 node.

## Log
- **2026-06-02 (builder-3-211218): partial — BLOCKED on host coordination.**
  **Done & committed (regression-safe):**
  - `jobs/agent-mesh.hcl` cred mounts are now node-portable: sources derive from dynamic node
    meta `${meta.agent_home}` instead of hard-coded `/home/ubuntu`. Targets stay `/home/ubuntu`
    (image's user) so in-container claude/codex find creds regardless of host owner.
  - Wired `agent_home` via dynamic node meta (persists across restarts, no `cluster/` edits):
    `oraclebox1=/home/ubuntu`, `V1410-1=/home/e`, `bigo-server=/home/bigo` (found by probing).
  - Replaced the `oraclebox1` node-name pin with a `${meta.agent_mesh_ready}=true` gate, set
    **only on oraclebox1** for now. Verified: an idle dispatch resolves only to oraclebox1 and
    does NOT fall to the amd64 nodes (which have free CPU) → briefed agents can't land on the
    still-broken nodes. No regression to the working oraclebox1 path.
  - Verified the multi-arch image + tsnet sidecar **run on V1410-1**: a test agent joined the
    tailnet (`agent-credverify-v1410`, ip 100.92.13.44, mesh api up) before failing on the repo
    mount — so arch/mesh are fine; only creds+repo block briefed work.

  **Two blockers (need host-level access I can't safely do/verify remotely):**
  1. **Stale host checkouts.** `$agent_home/monad` on V1410-1 (`/home/e/monad`) and bigo-server
     (`/home/bigo/monad`) are stale — missing `meta/agent/run-agent.sh` (and
     `scripts/maintenance-agent.sh`). Mounting them at `/work` overlays outdated code → the
     briefed agent died with `exit 127: /work/meta/agent/run-agent.sh: No such file`. Fix: a
     SAFE `git -C $repo pull --ff-only` **only if clean** (never discard local work), as the
     owning user. This also fixes the related maintenance-agent engine gap (see below).
  2. **Container uid mismatch.** The image runs `ubuntu` as **uid 1001** (oraclebox1's), but
     V1410-1's user `e` is **uid 1000** (bigo-server's `bigo` uid TBD). Mode-600 creds aren't
     readable across uids. Fix: per-host image build with `--build-arg AGENT_UID=<host uid>`
     (Dockerfile already supports it) pushed under a per-arch/uid tag, OR loosen cred perms.

  **Maintenance-agent engines on amd64 (acceptance item 2):** same root cause as blocker #1 —
  the launcher in `jobs/maintenance-agent.hcl` only su's to a credentialed user if that user's
  `$home/monad` has `maintenance-agent.sh`; on amd64 it's stale, so it runs the engine-less
  alloc-local clone as root (`no engine ready`). The same ff-only-if-clean update would let it
  su to `e`/`bigo` (who have claude+codex), giving a ready engine. Left for a follow-up because
  ff-updating a user's live checkout, then switching the agent to run as that user, risks the
  mesh-attach sidecar cache/docker-access path that currently works as root — needs care +
  on-node verification so [[amd64-maintenance-mesh]]'s mesh membership isn't regressed.

  **Next builder:** start with blocker #1 (a clean ff-only update of the two host checkouts,
  e.g. via a raw_exec job per node that pulls as the owning user only when `git status
  --porcelain` is empty), re-test the briefed dispatch on V1410-1, then tackle the uid build (#2)
  and flip `agent_mesh_ready=true` per node as each passes.

- **2026-06-02 (agent-builder-3-221913) — blocker #1 RESOLVED a different (non-destructive)
  way; acceptance items 1 & 3 met.** Rather than fixing the wrong-origin host checkouts (the
  owner-gated destructive re-point tracked in [[amd64-agent-checkout-sync]] #11), I made
  `jobs/agent-mesh.hcl` clone a FRESH correct-origin repo into the alloc-local `/work` per
  dispatch (like `fleet-builder.hcl`), removing the host-checkout dependency entirely. See
  [[agent-mesh-alloc-clone]] (#15, done). Verified: a briefed dispatch landed + ran healthy on
  **V1410-1** (amd64), exit 0, `/work` had `run-agent.sh`, origin =
  `https://github.com/eliott-monad/monad`. So **acceptance item 1** (repo no longer a
  hard-coded mount; creds derive from `meta.agent_home`) and **item 3** (briefed dispatch runs
  on a non-oraclebox1 node) are satisfied. **Item 2** (amd64 `maintenance-agent` reports a
  ready engine) is still open — that's the `jobs/maintenance-agent.hcl` launcher su-ing to a
  credentialed user, a separate change. Leaving this project's status to its owner; the mesh
  half is unblocked.

- **2026-06-03 ~00:08 (agent-builder-3-234153) — DONE. All three acceptance items now met.**
  This project's last open item was **acceptance item 2** (an amd64 `maintenance-agent` reports
  a ready engine + completes a self-pass `last` exit_code=0). That was tracked as
  [[amd64-maintenance-engine]] (#18) and is now **complete + verified**:
  - **bigo-server**: `monad/maintenance/bigo-server/last` **exit_code=0** (2026-06-02T23:56:00Z),
    engine ran as non-root user `bigo` (`agent_engines` includes claude → non-empty). ✅
  - **V1410-1**: drained its previously-stuck delegated task with **exit_code=0**, engine as
    non-root user `e`. ✅
  - **oraclebox1**: unchanged, exit_code=0 — no regression. ✅
  Items 1 & 3 were already met (builder-3-221913, via [[agent-mesh-alloc-clone]] #15: cred
  mounts derive from `${meta.agent_home}`, the oraclebox1 pin is now the flippable
  `${meta.agent_mesh_ready}` gate, and a briefed dispatch ran healthy on amd64 V1410-1). The two
  original blockers are resolved by siblings: blocker #1 (stale host checkouts) sidestepped by
  #15's per-alloc fresh clone; blocker #2 (uid mismatch) by [[amd64-agent-uid-image]] (#12,
  image `:uid${meta.agent_uid}` + node meta `agent_uid` wired). Closing #9.
  Credit: builder-3-211218 (portable mounts + meta), builder-3-221913 (#15 alloc-clone),
  builder-3-223648 (#18 code fix 43a1fae), agent-builder-3-234153 (#18 finish/verify + closure).
