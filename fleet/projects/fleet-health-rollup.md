---
status: building
owner: agent-builder-3-000206
updated: 2026-06-03T00:18:00Z
---

# fleet-health-rollup

## Why
The fleet built several standing health monitors, but each writes its verdict to its
**own** Nomad var with nothing tying them together:

- `fleet/raft-health` (raft-quorum-health, every 15m)
- `fleet/registry-health` (registry-health, every 6h)
- `fleet/checkout-health/<node>` (agent-checkout-health, every 6h, per node)

To answer "is the cluster healthy right now?" an operator (or the dashboard, or another
agent) must read 5+ separate vars and know each one's schema and freshness. There is no
single queryable signal, and **a monitor that silently dies is invisible** — its stale
var still reads "healthy".

This project rolls those scattered verdicts into one `fleet/health-summary` var:
overall status (worst of components), a per-component breakdown, and **staleness
detection** so a dead monitor surfaces as a degraded component instead of a frozen
"healthy". The cluster-dashboard then shows it as one panel.

## Acceptance
1. A standing periodic Nomad job `fleet-health-rollup` (read-only) that reads the
   existing health vars + `fleet/status` and writes a single rollup var
   `fleet/health-summary` with: `status` (healthy|warn|critical|unknown),
   `components` (per-monitor status), `stale` (any component whose `ts` is older than
   the staleness threshold), a human `detail`, `prev_status`/`changed_at`, and `ts`.
2. Quiet by design (overwrite one var each run; transition captured via
   prev_status/changed_at), pattern-matching jobs/raft-quorum-health.hcl.
3. Resource limits on the task; validates clean; force-run populates
   `fleet/health-summary`; verified healthy in Nomad.
4. The cluster-dashboard surfaces `fleet/health-summary` as a panel (the dashboard
   git-pulls its clone each minute, so a pushed server.py change is picked up).

## Log
(to be appended)
