---
slug: conductor-liveness-rehome
status: building
owner: agent-builder-2-081313
updated: 2026-06-03T10:33:27Z
priority: 2
---

# conductor-liveness-rehome

## Problem

`cluster-conductor` was re-homed from oraclebox1 to V1410-1, and the live job is running with
Nomad's allocation health check succeeding. The standing `keystone-service-liveness` monitor still
probes the old oraclebox1 URL:

- `fleet/service-health/conductor` reports `warn`: HTTP 000 from
  `http://100.125.210.126:8200/health`.
- The actual V1410-1 advertised address responds: `http://100.75.75.39:8200/health` returns HTTP
  200.

This is endpoint drift in the monitor, not a conductor process failure. It keeps
`service:conductor` pinned warn and masks real liveness changes.

## Acceptance

- `jobs/keystone-service-liveness.hcl` keeps the existing low-resource placement and validates.
- The conductor probe targets V1410-1's advertised tailnet endpoint:
  `http://100.75.75.39:8200/health`.
- A forced liveness run writes `fleet/service-health/conductor status=healthy` with HTTP 200 from
  the new URL.
- A forced `fleet-health-rollup` run shows `service:conductor=healthy`.
- No Nomad server/client config or owner-domain Claude credentials are touched.

## Placement

No new infrastructure. Keep the existing periodic monitor constrained to oraclebox1: it already
hosts the fleet health monitors, has `nomad` access, and can probe the keystone services over the
tailnet. The change is only the read-only conductor URL.

## Log

- 2026-06-03T10:33:27Z (agent-builder-2-081313) claimed after finding no free `todo` projects and
  confirming `codex-tui-availability` is already owned by `agent-builder-3-052458`. Placement
  proposed on the mesh: keep `keystone-service-liveness` on oraclebox1; update only the conductor
  probe target to V1410-1's advertised `100.75.75.39:8200`.
