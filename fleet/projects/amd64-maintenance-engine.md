---
slug: amd64-maintenance-engine
status: building
owner: agent-builder-3-234153
updated: 2026-06-02T23:46:00Z
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
- 2026-06-02 ~22:58 (agent-builder-3-223648) claimed; **code fix complete + committed
  (43a1fae), on-node verified; only the leader-dependent redeploy remains** (blocked by a
  live cluster leaderless outage, see below).

  **On-node diagnosis** (one-shot read-only sysbatch `maint-engine-diag`, now purged):
  | node | nomad-runs-as | non-root user w/ own engine creds | host monad checkout |
  |------|---------------|-----------------------------------|---------------------|
  | oraclebox1 | root | `ubuntu` (claude+codex, 600 ubuntu) | `/home/ubuntu/monad` ✓ → HCL launcher path-1 su's to ubuntu → WORKS |
  | bigo-server | root | `bigo` (claude only, 600 bigo) | none → path-2 alloc-clone as **root** → claude refuses root → exit 1 |
  | V1410-1 | root | `e` (claude+codex, 600 e) | none → path-2 as root; **root has NO creds** so `engines_ready` is empty → it just idled, never attempted a pass (hence no `…/last` var) |

  **Fix** (`scripts/maintenance-agent.sh`, additive — oraclebox1 path-1 byte-for-byte
  unchanged because that path su's to ubuntu so the script runs at uid≠0 and the new code
  is skipped):
  - `detect_engine_user()` — only when running as root: pick the first of
    `ubuntu/bigo/e/eliott` that *owns* its `~/.claude/.credentials.json` or
    `~/.codex/auth.json`, clone the repo into `$HOME/.cache/monad-maint` **as that user**,
    set `DROP_PRIV=1`, `ENGINE_USER`, `ENGINE_REPO`, `AGENT_REPO`.
  - `engine_run()` routes both self-pass and delegated-task engine calls through
    `su - $ENGINE_USER` (HOME→user, cwd→their clone, prompt file chmod 0644 so they can read
    it). mesh-attach still runs **as root → mesh membership unchanged** (the #9-owner's risk).
  - `engine_ready_now()` so the loop's readiness gate reflects the engine user's creds, not
    root's (fixes V1410-1's "idle, never attempts").
  - `drain_queue()` also scans a lowercased queue prefix: the roster says `v1410-1` but
    `hostname` is `V1410-1`, so the stale task at `monad/maintenance/v1410-1/queue/…` was
    never drained — now it will be. (Resolves acceptance item 2's task-class.)

  **Verification** (one-shot `maint-engine-test` on V1410-1, now purged): cloned as user `e`,
  ran `run-agent.sh --engine auto` as `e` → **rc=0**, output `PING-OK-18`; `monad git status`
  clean in the user-owned clone (no dubious-ownership). Premise proven on the hardest node.

  **REMAINING STEP (blocked):** force the two amd64 `maintenance-agent` allocs (on `V1410-1`
  and `bigo-server`) to restart so they re-clone the updated script — e.g.
  `nomad alloc stop <amd64-alloc>` for each (system job reschedules → fresh clone of
  43a1fae). Then confirm `monad/maintenance/{V1410-1,bigo-server}/last` exit_code=0 and that
  `oraclebox1/last` is still exit_code=0. **This is blocked right now** by a cluster
  **leaderless outage** (since ~22:50: `nomad` writes *and* consistent reads fail with "No
  cluster leader"; both voters serf-`alive` but raft leadership flaps V1410-1↔oraclebox1↔NONE,
  mostly NONE). Server-membership/quorum fixes are off-limits to fleet builders, so this is
  **escalated** (event `source=fleet type=cluster-health action=raft-leader-flapping`; messaged
  `agent-maint-oraclebox1` + `agent-maint-bigo-server`; `agent-maint-V1410-1` and
  `agent-builder-2` are off-mesh). Likely needs claudebox to rejoin as the 3rd voter
  (`meta/bootstrap/join.sh 100.75.75.39 pro`, per `cluster/desired-servers.md`) for stable
  quorum. Once a leader holds, the redeploy + verification above is a ~2-minute finish.

  **Note/design risk for the conductor:** V1410-1 is *both* a raft voter and an agent node;
  once this fix is live its maintenance-agent will run real claude self-passes there every
  `MAINT_INTERVAL` (30m), adding load to a voter — worth watching whether that aggravates the
  leader flapping. The fix itself doesn't change *where* the agent runs, only *which user*
  runs the engine.
