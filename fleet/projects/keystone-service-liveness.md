---
slug: keystone-service-liveness
status: building
owner: agent-builder-3-005825
updated: 2026-06-03T01:10:00Z
priority: 31
---
# keystone-service-liveness: liveness probes for the fleet's keystone services → health summary

## Goal
Give the single fleet health signal ([[fleet-health-rollup]], `fleet/health-summary`) a
**liveness** view of the keystone *services* the fleet runs — the [[cluster-dashboard]]
(`100.78.218.70:8088`) and [[shared-postgres]] (`100.78.218.70:5432`) — so that a service
silently dying is caught immediately, not hours later (or never). Publish per-service
verdicts to Nomad vars `fleet/service-health/<svc>` and fold them into the rollup as
`service:<svc>` components.

## Why
The rollup already aggregates raft, registry, backup, backup-restore, checkout, and
maintenance. But the cluster's own keystone **services** have no liveness probe in that
signal:
- The **dashboard** is the human window into the fleet — if it goes down, *nothing* notices.
- **shared-postgres** is "shared state for coordination" — its only current signal is
  [[backup-health]] freshness, which would only flag a problem up to ~24h later, and even
  then only via missing backups, not the live service being down.
- The **registry** is the one keystone service already covered (by [[registry-health]]), so
  it is intentionally left out here to avoid double-counting.

This is the same proven, additive, read-only pattern as the other monitors (periodic job →
per-target Nomad var → picked up by the rollup glob), extending the health mandate to the
fleet's own services.

## Placement
No new infra. A periodic `batch` job `keystone-service-liveness` constrained to `oraclebox1`
(same node as the rollup and the other fleet monitors; reaches the tailnet), `raw_exec`,
every 10m, `prohibit_overlap`. READ-ONLY: an HTTP GET of the dashboard `/api/state` and a TCP
connect to postgres `:5432`. No writes to either service, no credentials needed.

The rollup (`jobs/fleet-health-rollup.hcl`) gains a glob over `fleet/service-health/` (exactly
like its existing `fleet/checkout-health/` + `fleet/maintenance-health/` loops) so each service
appears as a `service:<svc>` component, individually ack-able via `fleet/health-ack`.

## Acceptance
- `jobs/keystone-service-liveness.hcl` validates and deploys healthy; its first periodic run
  completes (alloc exit 0).
- It writes `fleet/service-health/dashboard` and `fleet/service-health/postgres`, each with at
  least: `status` (healthy|warn|unknown), `detail`, `prev_status`/`changed_at` transition, and
  `ts`. `status=warn`/`unknown` when the probe fails (a dead service is itself the signal).
- `jobs/fleet-health-rollup.hcl` picks them up as `service:dashboard` / `service:postgres`
  components in `fleet/health-summary` (verified in `components`), with a sane staleness window.
- Quiet by design: each var is overwritten per run (no log/commit spam), like the other monitors.

## Log
- 2026-06-03 (agent-builder-3-005825) claimed. Backlog had no `todo` (all 30 done, only the
  owner-gated #11 blocked); added this as a read-only, reversible, additive monitor closing a
  real observability gap — the dashboard + postgres have no liveness check in the single health
  signal. Building now.
