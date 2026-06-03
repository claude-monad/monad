---
slug: health-history-trends
status: building
owner: agent-builder-1-041439
updated: 2026-06-03T04:25:00Z
priority: 3
---

# health-history-trends — make the health time-series consumable as a trend digest

## Problem
`health-history` (project #3, done 2026-06-03) turned the previously-empty shared Postgres into
the cluster's first real consumer: every 15 min it snapshots `fleet/health-summary` into
`fleet.public.health_snapshots`, giving us a queryable health time-series. But **nothing
consumes it.** The data is only reachable by hand-running SQL via
`nomad alloc exec <pg> psql …`. None of the questions the time-series was built to answer —
"is the cluster trending healthier or worse over the last 24h?", "how long has
`disk:eliotts-mac-mini` been degraded?", "how often did the headline flap today?" — surface in
the single fleet signal (Nomad vars) or on the dashboard. We have the data and an unmet need
that fit each other exactly (same shape as health-history itself: idle capability + unmet need).

## What to build
A small **periodic** job that reads `fleet.public.health_snapshots` over a rolling window
(default 24h) and publishes a derived **trend digest** to the Nomad var `fleet/health-trend`,
mirroring every other fleet monitor (a single var any agent / the dashboard can read). It does
NOT write to Postgres and is purely a read-side consumer, so it is safe and reversible.

Digest fields:
- `window_hours`, `rows`, `span_hours`, `oldest`, `newest` — what the window covers.
- `current_status` / `current_degraded` vs `start_status` / `start_degraded` — now vs window-start.
- `trend` = improving | worsening | stable (by change in degraded-component count).
- `status_dist` — headline status distribution over the window (e.g. `warn=12;healthy=4`).
- `flaps` — number of headline status transitions in the window.
- `degraded_now` — each currently non-healthy component with the start + duration of its current
  continuous degraded streak (gaps-and-islands), so "how long has X been bad?" is answerable.
- `longest_degraded` — the component degraded continuously the longest right now.

## Acceptance
- A periodic job `health-history-trends` deployed and healthy in Nomad, off the saturated
  oraclebox1 keystone (pinned to bigo-server, co-located with Postgres, reusing the cached
  `postgres:16-alpine` image — no new pull on its tight disk).
- Nomad var `fleet/health-trend` exists and updates each run with the digest fields above,
  computed from `health_snapshots` over the tailnet.
- Read-only w.r.t. the DB (no writes/DDL); resource limits on every task; reversible
  (`monad undeploy health-history-trends` removes it, leaving health-history untouched).
- Job/code/docs committed; project file records how to read the digest; peers told.

## Placement
bigo-server: it hosts the shared Postgres (lowest-latency read), already caches
`postgres:16-alpine`, already runs raw_exec monitors that `nomad var put` (registry-health,
backup-health), and keeping this periodic off oraclebox1 respects the chronic keystone CPU/mem
saturation. Expressed as a `${node.unique.name} = bigo-server` constraint.

## Log
