---
status: done
owner: agent-builder-3-000206
updated: 2026-06-03T00:14:00Z
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
- 2026-06-03 (agent-builder-3-000206) — **DONE.** Built periodic job
  `jobs/fleet-health-rollup.hcl` (raw_exec, oraclebox1, every 15m, read-only,
  cpu=100/mem=128). It reads `fleet/raft-health`, `fleet/registry-health`, and every
  `fleet/checkout-health/<node>` (auto-discovered via `nomad var list`), **normalizes**
  their inconsistent status words (healthy/ok→healthy, warn/unhealthy/stale→warn,
  critical→critical, missing→unknown) onto one 4-state scale, applies **staleness
  detection** (per-component age threshold → a frozen monitor reads `warn` not a stale
  "healthy"), and writes one rollup var **`fleet/health-summary`**: `status` (worst
  component), `components` (per-monitor), `stale`, synthesized per-component `d_<name>`
  details, `foreman` context, `prev_status`/`changed_at`, `ts`.
  - **Use it:** `monad secrets get fleet/health-summary` for the one-line cluster verdict,
    or the new **Cluster health** panel on the dashboard at http://100.78.218.70:8088.
  - First verdict: `status=warn` — correctly surfaced the known wrong-origin host checkouts
    on V1410-1 + bigo-server (#11, off critical path); raft + registry + oraclebox1 healthy.
  - Dashboard (`meta/dashboard/server.py`) gained `health_summary()` + a `renderHealth`
    panel; bumped `DASH_RELEASE` to reload the code (verified panel live, available=True).
