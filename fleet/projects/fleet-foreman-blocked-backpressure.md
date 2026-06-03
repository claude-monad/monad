---
slug: fleet-foreman-blocked-backpressure
status: building
owner: agent-builder-2-031239
updated: 2026-06-03T03:37:36Z
priority: 3
---

# fleet-foreman-blocked-backpressure

## Problem
After the backlog was completed, only `amd64-agent-checkout-sync` remained `blocked` for an
owner-gated destructive checkout re-point. `scripts/fleet-foreman.sh` still computes:

```
open = B_TODO + B_BUILDING + B_BLOCKED
```

That makes the standing foreman target `FOREMAN_N=3` builders even when there is no actionable
work for builders to claim. On 2026-06-03 this left two fleet-builder dispatches running on
oraclebox1 and a third pending, while `fleet/health-summary` reported
`overload:oraclebox1=warn` and the pending child could not place due CPU exhaustion.

## Acceptance
- `scripts/fleet-foreman.sh` treats only actionable states (`todo`, `claimed`, `building`,
  `review`) as open work for top-up; `blocked` stays visible in `fleet/status` but does not
  raise the builder target above the one watcher builder.
- `monad validate jobs/fleet-foreman.hcl` passes, and `monad deploy jobs/fleet-foreman.hcl`
  leaves the foreman service healthy.
- A foreman cycle with zero actionable projects and one blocked project writes
  `fleet/status target=1` and does not dispatch more builders.
- Any excess pending `fleet-builder` child that has no allocation is stopped/purged if it is
  still pending after the foreman fix. Running builders are left alone to finish naturally.

## Placement
No new infrastructure. `fleet-foreman` remains the existing raw_exec singleton on oraclebox1.
This change reduces unnecessary builder pressure on that keystone instead of moving services.

## Log
- 2026-06-03T03:37:36Z — claimed by agent-builder-2-031239 after verifying there were no
  `todo`/`building` project files, only owner-gated blocked #11, while `fleet-builder` showed
  2 running and 1 pending child constrained to oraclebox1.
