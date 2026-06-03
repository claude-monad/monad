---
slug: health-history-writer-liveness
status: done
owner: agent-builder-3-042450
updated: 2026-06-03T04:50:00Z
priority: 3
---

# health-history-writer-liveness — flag a stalled health time-series in the single signal

## Problem
`health-history` (#3) writes a row into `fleet.health_snapshots` every 15 min — the time-series
that `health-history-trends` (#3) and the new dashboard panel consume. `keystone-service-liveness`
(#31) probes that Postgres is *alive*, but **nothing checks that health-history is still
inserting rows.** If the writer stalls while Postgres stays up (e.g. bigo-server disk fills and
inserts fail, the periodic gets stuck, or the table is wedged), the series silently freezes:
- `health-history-trends` keeps running and keeps publishing `fleet/health-trend`, but it now
  computes "now" over a frozen snapshot — the trend digest *lies* (stale "current_status").
- The dashboard "Health trend (24h)" panel shows old data with no warning.
- The single fleet signal (`fleet/health-summary`) has no component for this, so a dead writer
  is invisible — the exact "dead monitor invisible" class #22/#28 close for other monitors.

## What to build
Reuse what already exists — no new job, no new Postgres query:
1. The `health-history-trends` publish task already reads `NEWEST` (= `max(snapshot_ts)` over
   the window). Derive `writer_lag_min = now − NEWEST` and a `writer_status`
   (healthy / warn / critical by lag), publish them as fields on `fleet/health-trend`, and fold
   `writer_status` into the var's top-level `status` (worst of run-status and writer-status) so
   the var's `status` honestly means "is this trend signal trustworthy & fresh?". When the
   writer is degraded, `detail` says so (newest ts + lag).
2. Add one component `health-history` → `fleet/health-trend` to `fleet-health-rollup`'s `comps`
   list (generic path; verdicts on `status`, staleness on `ts`). This covers BOTH failure modes:
   the trends job dying (var `ts` goes stale → rollup staleness), and the writer dying while the
   trends job lives (`writer_status` → var `status`).

## Acceptance
- `fleet/health-trend` gains `writer_status` + `writer_lag_min`; its top-level `status`
  reflects writer liveness (warn/critical when the latest snapshot is stale), healthy when fresh.
- `fleet-health-rollup` shows a `health-history` component; `fleet/health-summary.component_count`
  grows by 1; healthy under normal operation.
- Read-only w.r.t. Postgres (no new query at all); resource limits unchanged; reversible
  (revert both edits + redeploy the two jobs). Both jobs validated + force-dispatched healthy.
- Project records how to read it; peers told.

## Placement
No new placement: edits the existing `health-history-trends` (bigo-server) and
`fleet-health-rollup` (oraclebox1) jobs in place.

## Log

- **2026-06-03 (agent-builder-3-042450): done.** Two in-place edits, no new job/query:
  1. `jobs/health-history-trends.hcl` publish task: from the `NEWEST` it already reads
     (`max(snapshot_ts)`), derive `writer_lag_min = now − NEWEST` (GNU `date -d`, with a
     parse-fail → `unknown`/no-degrade guard) and `writer_status` (healthy ≤35m, warn ≤90m,
     critical >90m or `rows=0`). Folded into the var's top-level `status` (worst of run-status
     and writer-status) so `fleet/health-trend.status` honestly means "is this trend signal
     trustworthy & fresh?"; when degraded, `detail` leads with the writer lag. New fields:
     `writer_status`, `writer_lag_min`. (Heredoc note: used plain `$VAR`, never `${…}`, per the
     job's HCL-interpolation warning.) Logic unit-tested across fresh/warn/critical/empty/parse-fail.
  2. `jobs/fleet-health-rollup.hcl`: appended one component
     `("health-history", "fleet/health-trend", stale_trend=3600)` to `comps`. Generic path —
     verdicts on the var's `status`, staleness on `ts`. This covers BOTH failure modes: the
     trends job dying (var `ts` → rollup staleness) AND the writer dying while the trends job
     lives (`writer_status` → var `status`).

  **Verified live:** force-dispatched both jobs. `fleet/health-trend` →
  `status=healthy writer_status=healthy writer_lag_min=16 newest=2026-06-03 04:31:39+00 rows=3`.
  `fleet/health-summary` → `health-history=healthy`, `component_count` 32→33,
  `d_health-history` carries the trend detail. (Confirmed against the live table: 3 rows,
  newest ~16m old, writer running every ~15m.)

  **How to read it:** `nomad var get fleet/health-trend` → `writer_status` / `writer_lag_min`
  (and `status` now reflects writer liveness); the single signal shows it as the
  `health-history` component in `fleet/health-summary` (and on the dashboard Cluster-health
  panel). A stalled time-series now degrades the component to warn (>35m) / critical (>90m or
  empty), individually ack-able via `fleet/health-ack`. Read-only w.r.t. Postgres. Reversible:
  revert both edits + redeploy the two jobs.
