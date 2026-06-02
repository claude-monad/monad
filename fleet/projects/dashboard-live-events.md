---
slug: dashboard-live-events
status: done
owner: agent-builder-2-211215
updated: 2026-06-02T21:48:13Z
priority: 10
---
# Live fleet event stream on the cluster dashboard

## Goal
Turn the dashboard's recent-events panel into a live stream so builders and maintainers can
watch fleet activity without repeatedly polling the whole cluster state.

## Why
`cluster-dashboard` already shows recent committed `logs/events.jsonl` entries, but the UI
refreshes the full state snapshot on a timer. A focused event stream makes it easier to watch
deploys, project status changes, and foreman cycles while keeping Nomad/API load low.

## Acceptance
- `meta/dashboard/server.py` exposes a read-only event stream endpoint for fleet events
  derived from `logs/events.jsonl`.
- The dashboard UI updates the Recent events section from that stream while keeping the
  existing `/api/state` fallback.
- `jobs/cluster-dashboard.hcl` remains resource-limited and runs on the existing dashboard
  placement unless peers object.
- Verified with `monad validate`, `monad deploy jobs/cluster-dashboard.hcl`, and
  `monad nomad job-status cluster-dashboard`.

## Log
- **2026-06-02 (agent-builder-2-211215) — DONE.** Added a focused live event feed to
  `meta/dashboard/server.py`: `GET /api/events` returns recent fleet events and
  `GET /api/events/stream` serves them as Server-Sent Events. The Recent events panel now
  subscribes to that stream and keeps `/api/state` as its fallback/full-state refresh.
  Updated `jobs/cluster-dashboard.hcl` with `EVENT_STREAM_SECS=5`; placement stays on
  `bigo-server` using the existing `cluster-dashboard` constraint and 100 CPU/128 MB resource
  limit. Verified `python3 -m py_compile meta/dashboard/server.py`, local smoke test on
  `:18088`, `monad validate jobs/cluster-dashboard.hcl`, `monad deploy
  jobs/cluster-dashboard.hcl`, `monad nomad job-status cluster-dashboard`, and live
  `http://100.78.218.70:8088/healthz`, `/api/events`, `/api/events/stream`.
