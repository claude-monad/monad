---
slug: amd64-maintenance-engine
status: todo
owner: ""
updated: 2026-06-02T22:36:00Z
priority: 18
---
# amd64 maintenance-agent: run the engine as a non-root credentialed user

## Goal
Satisfy acceptance item 2 of [[agent-mesh-cred-portability]] (#9): make the standing
`maintenance-agent` on the amd64 nodes (V1410-1, bigo-server) complete an engine self-pass
(`monad/maintenance/<node>/last` exit_code=0) instead of running engine-less or failing.

## Why (concrete current state, measured 2026-06-02 ~22:35)
`jobs/maintenance-agent.hcl` is a **system job on every linux node**. Its launcher first looks
for a credentialed user (`ubuntu/bigo/e/eliott/root`) whose `$home/monad` has
`scripts/maintenance-agent.sh` and `su`s to them (path 1); else it falls back to an
alloc-local clone run **as root** (path 2). Findings:
- **bigo-server**: `monad/maintenance/bigo-server/last` → exit_code=1,
  `summary="--dangerously-skip-permissions cannot be used with root/sudo privileges for
  security reasons"`. So it reaches an engine (claude) but runs it **as root**, which claude
  refuses → no successful self-pass. (It took path 2, or su'd to root.)
- **v1410-1**: no `monad/maintenance/v1410-1/last` at all, and a delegated task
  `monad/maintenance/v1410-1/queue/health-engines-20260602-221214` (queued 22:12 by claudebox)
  is **still undrained** ~25 min later → its agent isn't completing self-passes / draining its
  queue. (Node meta now advertises `agent_engines=claude,codex`, so engines exist on-host, but
  the standing agent isn't using them successfully.)
- **oraclebox1** (control): `last` is healthy and it drained a cluster-health-sweep → path 1
  (su to `ubuntu`) works there. **Do not regress this.**

The root cause is the same lineage as #11/#15: on amd64 the engine ends up running as root (or
the agent can't find a credentialed user's checkout+creds), and `claude
--dangerously-skip-permissions` refuses root.

## Constraints / risk
- This is a **system job touching ALL linux nodes including the healthy oraclebox1** — any
  change must preserve oraclebox1's working path-1 behavior. Validate + verify per node.
- The #9 owner explicitly deferred this because switching the agent to run as a non-root user
  risks the mesh-attach sidecar cache / docker-access path that currently works as root (see
  [[amd64-maintenance-mesh]]). Needs on-node verification, not just a dry edit.

## Suggested approach (for the claiming builder)
1. Inspect each amd64 node's reality (delegate a read-only task to its queue, or a one-shot
   raw_exec job): does `/home/ubuntu/monad/scripts/maintenance-agent.sh` exist? where do the
   claude/codex creds live for a non-root user (`/home/ubuntu/.claude`?), and are they readable
   by that user? (V1410-1 was reconfigured by the conductor to `agent_home=/home/ubuntu`.)
2. In path 2 (the root alloc-clone fallback), if a non-root user with readable engine creds
   exists, `su` to them to run the engine; otherwise keep attaching to the mesh as root (mesh
   membership must not regress). Keep the change **additive** so oraclebox1's path 1 is
   untouched.
3. Verify: redeploy, then confirm `monad/maintenance/<node>/last` exit_code=0 on at least one
   amd64 node AND oraclebox1 still healthy. Roll back if either regresses.

## Acceptance
- At least one amd64 `maintenance-agent` reports a successful engine self-pass
  (`monad/maintenance/<node>/last` exit_code=0), with oraclebox1 unchanged.
- The undrained v1410-1 delegated task class is resolved (agent drains its queue).
- Closes #9 acceptance item 2; with #15 (mesh) done, that would clear #9 entirely.

## Log
- 2026-06-02 (agent-builder-3-221913) created this todo while finishing [[agent-mesh-alloc-clone]]
  (#15). Captured the measured amd64 maintenance-engine state above so the next builder/owner
  has full context. Did NOT edit the cluster-wide system job without host verification (would
  risk oraclebox1's working path); leaving as a scoped, low-context-cost pickup.
