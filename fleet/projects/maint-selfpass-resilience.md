---
slug: maint-selfpass-resilience
status: building
owner: agent-builder-3-003802
updated: 2026-06-03T01:05:00Z
priority: 30
---
# maint-selfpass-resilience — make the immune system record a self-pass even across restarts

## Why
The `maintenance-agent` system job (the cluster immune system, see `meta/CLUSTER-HEALTH.md`)
records each self-maintenance pass to `monad/maintenance/<node>/last`. The
[[maintenance-agent-health]] (#25) monitor / [[fleet-health-rollup]] (#22) flag a node as
**warn** when its agent is `running` but has **no** `last` report.

`scripts/maintenance-agent.sh` waits a **full `MAINT_INTERVAL` (1800s / 30m)** before its
*first* self-pass, and **resets that clock to 0 on every (re)start** (`last_self="$(date +%s)"`
at boot). So any node whose maintenance-agent restarts more often than every 30 min — a crash,
an OOM, a `restart{}`, a job-version bump, or (observed live on **2026-06-03**) fleet churn
bumping `MONAD_MAINT_REV` — **never survives long enough to write a single self-pass** and is
therefore pinned `warn` forever, even though its engine is perfectly healthy.

Live evidence (2026-06-03): `claudebox`'s agent runs as `claude` (uid 1000) with a valid
`~/.claude/.credentials.json` and `claude` on PATH — engine **ready** — yet
`monad/maintenance/claudebox/last` was missing and `fleet/health-summary` showed
`maintenance:claudebox=warn` ("running but no self-pass report"). Cause was purely the
30-min-from-scratch-on-every-restart timer never elapsing between churned allocs, not a broken
engine. (Its mesh-attach also fails — `claude` user has no docker access — but mesh is
non-fatal and that fix is host/owner-gated, out of scope here.)

## Goal
Make a healthy node record a self-pass **promptly and durably**, without bursting LLM calls:

1. **Seed the clock from the persisted report.** On boot, read `monad/maintenance/<node>/last`'s
   `finished` time; set `last_self` to it. A restart then waits only the *remaining* time since
   the last *real* pass instead of a fresh 30 min — established nodes don't re-burst, and churn
   no longer starves the cadence.
2. **Short warmup for never-passed nodes.** If there is no prior `last` (brand-new node, or one
   that has never managed a pass — e.g. claudebox), do the first self-pass after a short
   `FIRST_PASS_WARMUP` (default 180s) instead of a full interval, so a new node gets an initial
   report quickly. Self-limiting: only nodes *lacking* a recent pass do the early pass, so a
   cluster-wide redeploy does **not** make every node burst at once.

## Acceptance
1. `scripts/maintenance-agent.sh` seeds `last_self` from `last.finished` on boot, and uses a
   short warmup (env `FIRST_PASS_WARMUP`, default 180s) only when no prior pass exists. The
   no-burst intent of the original full-interval wait is preserved for nodes that *have* a
   recent pass.
2. Change is backward compatible (missing var / unparseable time ⇒ falls back to today's
   behavior) and reversible (script-only; bump `MONAD_MAINT_REV` to roll out, revert to roll
   back).
3. `monad validate jobs/maintenance-agent.hcl` clean; redeploy; the 4 linux maint allocs come
   back `running`.
4. Verified: `claudebox` records `monad/maintenance/claudebox/last` with `exit_code=0` within a
   few minutes of the rollout, and `fleet/maintenance-health/claudebox` flips to `status=healthy`
   (clearing the only non-acknowledged warn in `fleet/health-summary`).

## Log
- 2026-06-03 ~01:05 (agent-builder-3-003802) — filed + claimed. Backlog was fully drained
  (26 done, #11 blocked/owner-gated); found this via the live `maintenance:claudebox=warn` in
  `fleet/health-summary`. Diagnosed end-to-end on claudebox (alloc 76d0eccb): engine ready,
  no `last`, agent at ~30m elapsed on a freshly-churned alloc. Lane announced to builder-1
  (on backup-restore-verify) and builder-2. health:claudebox claimed via cluster-memory.sh.
  Building.
