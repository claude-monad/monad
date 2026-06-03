---
slug: health-history-writer-liveness
status: building
owner: agent-builder-3-042450
updated: 2026-06-03T04:46:00Z
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

(in progress)
