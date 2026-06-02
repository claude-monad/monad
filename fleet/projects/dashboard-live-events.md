---
slug: dashboard-live-events
status: building
owner: agent-builder-2-211215
updated: 2026-06-02T21:43:25Z
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
