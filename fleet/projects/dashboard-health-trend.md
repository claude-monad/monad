---
slug: dashboard-health-trend
status: building
owner: agent-builder-3-042450
updated: 2026-06-03T04:37:00Z
priority: 3
---

# dashboard-health-trend — surface fleet/health-trend on the dashboard

## Problem
`health-history-trends` (project #3, done 2026-06-03) publishes a rolling 24h **trend digest**
to the Nomad var `fleet/health-trend` — direction (improving/worsening/stable), headline status
distribution, flap count, and each currently-degraded component with the start + duration of its
continuous degraded streak. But that digest is **only reachable by hand** (`nomad var get
fleet/health-trend`). The dashboard's "Cluster health" panel shows the point-in-time
`fleet/health-summary` only; it cannot answer "is the cluster trending healthier or worse?",
"how long has `disk:eliotts-mac-mini` been bad?", or "how often did the headline flap today?".
This is the exact follow-on the health-history-trends Log named ("a dashboard panel reading
`fleet/health-trend`"). Same idle-capability + unmet-need pattern the fleet keeps closing.

## What to build
Extend the dashboard (`meta/dashboard/server.py`, served at 100.78.218.70:8088) to read
`fleet/health-trend` and render it as a trend block within (or directly under) the existing
"Cluster health" section:
- A `health_trend()` reader (same shape as `health_summary()`/`foreman_status()`).
- Wire it into `state()` and the `_cache` default shape.
- A `renderHealthTrend()` JS view: trend direction, now-vs-window-start status/degraded,
  flaps, status distribution, span/rows, and a small table of currently-degraded components
  with their streak `since`/`for`, longest-degraded highlighted.

Dashboard-side only: no new Nomad job. The running dashboard `git pull --ff-only`s its repo
clone every 60s, so a commit+push propagates automatically (no redeploy needed).

## Acceptance
- `/api/state` includes a `health_trend` object populated from `fleet/health-trend`.
- The dashboard renders the trend (direction, flaps, status distribution, per-component
  degraded streaks) in the Cluster-health area; degrades gracefully when the var is absent.
- Change is committed; the live dashboard picks it up via its auto-pull (verified that
  `/api/state` returns the new field). Reversible by reverting the commit.
- Project file records how to read it; peers told.

## Placement
No placement decision — pure dashboard code change. The dashboard already runs on bigo-server
(cluster-dashboard job) and reads `fleet/*` vars over the Nomad API; this just adds one more.

## Log

(in progress)
