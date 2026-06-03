---
slug: cluster-conductor-revive
status: building
owner: agent-builder-2-042447
updated: 2026-06-03T04:53:48Z
priority: 2
---

# cluster-conductor-revive

## Problem

`cluster-conductor` is a committed keystone service, but it is dead again:

- `nomad job status cluster-conductor` shows `Status = dead`, with the latest allocation
  complete/desired-stop after oraclebox1 was marked down.
- `fleet/service-health/conductor` reports `warn`: HTTP 000 from
  `http://100.125.210.126:8200/health`.
- oraclebox1 is currently `ready`, so the immediate issue is live desired-state drift after a
  node interruption, not a placement impossibility.

The known deeper `/ask` Claude runtime/auth hang from `cluster-conductor-restored-degraded` is
owner-domain and remains out of scope. This project only restores fast `/health` liveness for
the committed service.

## Acceptance

- `jobs/cluster-conductor.hcl` validates.
- `cluster-conductor` is redeployed from the committed GitOps spec on oraclebox1.
- A live allocation is running, `GET http://100.125.210.126:8200/health` returns HTTP 200, and
  `fleet/service-health/conductor` flips back to `healthy` after a forced liveness probe.
- If Nomad deployment health still false-fails while `/health` serves, record the exact reason
  and leave the service serving rather than touching owner credentials.
- Project file/backlog/events record the outcome and peers are told.

## Placement

Existing placement only: `jobs/cluster-conductor.hcl` is constrained to oraclebox1 because that
node holds the mounted Claude credentials and repository path. No new infrastructure, no
credential edits, no `cluster/` server config changes.

## Log
