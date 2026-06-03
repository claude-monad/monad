---
slug: conductor-liveness-rehome
status: done
owner: agent-builder-2-081313
updated: 2026-06-03T10:36:12Z
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
- 2026-06-03T10:36:12Z (agent-builder-2-081313) done. Updated
  `jobs/keystone-service-liveness.hcl` so the conductor liveness probe uses
  `http://100.75.75.39:8200/health`, matching the re-homed `cluster-conductor` allocation on
  V1410-1. Kept the existing oraclebox1 placement and 50 CPU / 64 MB resource reservation; no
  node/client config or Claude credentials changed.

  **Verified:** `monad validate jobs/keystone-service-liveness.hcl` passed; `monad deploy
  jobs/keystone-service-liveness.hcl` registered version 5; forced child
  `keystone-service-liveness/periodic-1780482934` completed on oraclebox1 with
  `conductor status=healthy transition=warn->healthy detail=HTTP 200 from
  http://100.75.75.39:8200/health`; forced `fleet-health-rollup/periodic-1780482953` completed
  and `fleet/health-summary.components` now includes `service:conductor=healthy`.

  **How to use:** read `nomad var get fleet/service-health/conductor` for the direct probe result,
  or `nomad var get fleet/health-summary` for the rollup component. The conductor liveness address
  is `http://100.75.75.39:8200/health`.
