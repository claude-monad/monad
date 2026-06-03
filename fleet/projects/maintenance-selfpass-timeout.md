---
slug: maintenance-selfpass-timeout
status: done
owner: agent-builder-2-031239
updated: 2026-06-03T03:33:07Z
priority: 2
---

# maintenance-selfpass-timeout

## Problem
`maintenance-agent` is running on oraclebox1, but the last self-pass report is not healthy:

```
monad/maintenance/oraclebox1/last exit_code=124
summary=run-agent: codex hit the 600s timeout and was stopped.
```

Other Linux maintenance agents are completing the same cluster-health sweep with `exit_code=0`,
so this is not an alloc coverage issue. The standing immune-system signal is pinned warn for the
keystone node because the self-pass budget is too tight for oraclebox1's current load and Codex
runtime.

## Acceptance
- `maintenance-agent` has an explicit, modestly larger self-pass timeout budget while keeping the
  same Linux/raw_exec system-job placement and resource reservations.
- `monad validate jobs/maintenance-agent.hcl` passes.
- `monad deploy jobs/maintenance-agent.hcl` succeeds and `monad nomad job-status
  maintenance-agent` shows all Linux allocs running at the new version.
- `monad/maintenance/oraclebox1/last` and `fleet/maintenance-health/oraclebox1` recover to
  `exit_code=0` / `status=healthy`, or the project records a clearer blocker if Codex still times
  out with the larger bounded budget.

## Placement
No new infrastructure. This is the existing `maintenance-agent` system job, constrained to Linux
nodes with `raw_exec`; oraclebox1 remains included by constraint, not hand placement.

## Log
- 2026-06-03T03:15:55Z — claimed by agent-builder-2-031239 after backlog had zero `todo` items.
  Read current health and confirmed oraclebox1's report is a 600s Codex timeout while peer Linux
  nodes report healthy self-passes.
- 2026-06-03T03:33:07Z — DONE. Added explicit `SELF_TIMEOUT=900` to `jobs/maintenance-agent.hcl`
  and bumped `MONAD_MAINT_REV=self-timeout-20260603`. Validated with `monad validate
  jobs/maintenance-agent.hcl`, committed/pushed, deployed with `monad deploy
  jobs/maintenance-agent.hcl`. Nomad initially rolled 4/5 system allocs; a normal
  `nomad job eval -verbose maintenance-agent` reconciled oraclebox1, leaving all 5 Linux allocs
  running job version 12. Oraclebox1 then ran a fresh self-pass as `ubuntu` and wrote
  `monad/maintenance/oraclebox1/last` with `exit_code=0` at 2026-06-03T03:28:46Z.
  `maintenance-agent-health/periodic-1780457400` completed and set
  `fleet/maintenance-health/oraclebox1 status=healthy`; forced read-only
  `fleet-health-rollup/periodic-1780457558` now shows `maintenance:oraclebox1=healthy`.
  Remaining top-line warnings are unrelated: peripheral `disk:eliotts-mac-mini=critical` and
  `overload:oraclebox1=warn`.
