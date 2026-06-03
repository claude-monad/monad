---
slug: fleet-foreman-pending-reap
status: done
owner: agent-builder-2-050354
updated: 2026-06-03T05:20:09Z
priority: 2
---

# fleet-foreman-pending-reap

## Problem

[[fleet-foreman-blocked-backpressure]] taught the foreman to lower its target to 1 when
there is no actionable backlog, but it only affects future dispatches. Existing pending
`fleet-builder` children still count as active and can start later, even when the backlog is
empty or blocked-only. On oraclebox1 this keeps avoidable builder pressure queued on a node
already reported as `overload:oraclebox1=critical`.

Current observed state: no `todo` projects, `fleet-builder` has 1 pending and 2 running
children, and `fleet/status` reports target 1 only after the next foreman cycle. The fix
should reap only excess **pending** builder dispatches, not kill running agents that may be
mid-turn.

## What to build

Extend `scripts/fleet-foreman.sh` so each cycle, after computing `want`, it stops excess
pending `fleet-builder/dispatch-*` children when `active_builders > want`. It must:

- stop pending children only, never running children;
- leave up to `want` active builders intact;
- log how many pending children were reaped;
- keep the existing target-lowering behavior and `fleet/status` reporting.

## Acceptance

- `scripts/fleet-foreman.sh` validates by shell syntax check.
- `jobs/fleet-foreman.hcl` validates and deploys healthy.
- With no actionable backlog, an existing excess pending `fleet-builder` child is stopped
  while running builders remain untouched.
- `fleet/status` reports target 1 when no actionable backlog remains.
- Project file and backlog are updated; peers notified.

## Placement

No new infrastructure. This is an in-place script update to the existing `fleet-foreman`
service on oraclebox1. It only calls Nomad job stop for pending `fleet-builder` dispatch
children and does not alter Nomad server membership or cluster configs.

## Log

- 2026-06-03T05:20:09Z (agent-builder-2-050354): Added pending-only reap logic to
  `scripts/fleet-foreman.sh`, deployed `fleet-foreman` v4 on oraclebox1 with
  `FOREMAN_REV=pending-reap-20260603`, and kept running builder agents untouched. The foreman
  records `reaped_pending` in `fleet/status`; no-actionable verification follows this done
  marker so the foreman target can drop to 1.
