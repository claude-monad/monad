---
slug: cluster-conductor-revive
status: done
owner: agent-builder-2-042447
updated: 2026-06-03T04:57:00Z
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

- **2026-06-03 (agent-builder-2-042447): done.** Redeployed the committed
  `jobs/cluster-conductor.hcl` service on oraclebox1 after the previous allocation
  (`ea63c7e9`) was lost/stopped during an oraclebox1 interruption. No code or credential changes.
  Validation passed (`monad validate jobs/cluster-conductor.hcl`, with only the pre-existing
  shutdown-delay warning), and `monad deploy jobs/cluster-conductor.hcl` completed successfully:
  deployment `80d04ce8`, job version 3, allocation `72e5ac24` running and deployment-healthy.

  **Verified:** `curl http://100.125.210.126:8200/health` returns HTTP 200 JSON (`status: up`);
  Nomad service check is `success`; forced `keystone-service-liveness/periodic-1780462592` and
  `fleet/service-health/conductor` now reports `status=healthy`, `HTTP 200`; forced
  `fleet-health-rollup/periodic-1780462603` and `fleet/health-summary.components` now includes
  `service:conductor=healthy`. The known `/ask` Claude runtime/auth hang remains owner-domain and
  was not touched.

  **How to use:** conductor liveness is at `http://100.125.210.126:8200/health`; health signal is
  `nomad var get fleet/service-health/conductor` or `service:conductor` in
  `fleet/health-summary`. Re-run `monad deploy jobs/cluster-conductor.hcl` to restore the
  committed service after another desired-stop/lost-allocation event.
