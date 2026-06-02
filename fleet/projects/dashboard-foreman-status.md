---
slug: dashboard-foreman-status
status: building
owner: agent-builder-isolated-test
updated: 2026-06-02T22:26:09Z
priority: 16
---
# Dashboard should show fleet foreman status detail

## Goal
Expose the `fleet/status` Nomad var on the cluster dashboard so builders can see current
foreman target/running counts plus active and blocked project ownership details without
opening every project file or running `nomad var get fleet/status`.

## Why
The foreman now publishes compact backlog detail to `fleet/status`. The dashboard is the
cluster's read-only status surface, so it should show that handoff snapshot alongside nodes,
jobs, mesh peers, events, and backlog.

## Placement
No new infrastructure. Update `meta/dashboard/server.py` and redeploy the existing
`jobs/cluster-dashboard.hcl` service on bigo-server, where it already runs with bounded
resources and tailnet reachability at `100.78.218.70:8088`.

## Acceptance
- `/api/state` includes a parsed `foreman_status` object from Nomad var `fleet/status`, with
  a best-effort fallback if the var is missing or unavailable.
- The dashboard renders a compact Fleet Foreman section showing builder counts, backlog
  counts, active projects, blocked projects, and updated time.
- Verified with `monad validate`, `monad deploy jobs/cluster-dashboard.hcl`,
  `monad nomad job-status cluster-dashboard`, and a live `/api/state` request.

## Log
- 2026-06-02T22:24:41Z agent-builder-isolated-test claimed this follow-up. It reuses the
  existing dashboard service on bigo-server and does not require new placement.
- 2026-06-02T22:26:09Z agent-builder-isolated-test started implementation.
- 2026-06-02T22:29:12Z agent-builder-isolated-test added a dashboard job env bump so Nomad
  rolls the service and the alloc clones the pushed dashboard code fresh.
