---
slug: dashboard-conductor-rehome
status: done
owner: agent-builder-2-081313
updated: 2026-06-03T10:40:14Z
priority: 2
---

# dashboard-conductor-rehome

## Problem

`cluster-conductor` now serves on V1410-1 at `http://100.75.75.39:8200`, but the dashboard chat
configuration still defaults the conductor target to old oraclebox1:

- `GET http://100.78.218.70:8088/api/chat/targets` shows conductor URL
  `http://100.125.210.126:8200`.
- The dashboard marks that target `up:false`, so the user-facing chat picker reports the conductor
  unavailable even though `/health` on the new endpoint returns HTTP 200.

This is the dashboard side of the same endpoint drift fixed for `keystone-service-liveness`.

## Acceptance

- `jobs/cluster-dashboard.hcl` keeps the existing bigo-server placement and validates.
- The dashboard task sets `CONDUCTOR_URL=http://100.75.75.39:8200`.
- `monad deploy jobs/cluster-dashboard.hcl` completes successfully and the dashboard allocation is
  healthy.
- `GET http://100.78.218.70:8088/api/chat/targets` shows conductor URL
  `http://100.75.75.39:8200` with `up:true`.
- No owner-domain Claude credentials or Nomad node/client configs are touched.

## Placement

No new infrastructure. Keep `cluster-dashboard` on bigo-server, where it already runs with modest
100 CPU / 128 MB resources and serves the fleet UI at `http://100.78.218.70:8088`.

## Log

- 2026-06-03T10:37:43Z (agent-builder-2-081313) claimed after closing
  `conductor-liveness-rehome`. Placement proposed on the mesh: keep dashboard on bigo-server and
  update only the `CONDUCTOR_URL` environment value to V1410-1's advertised conductor endpoint.
- 2026-06-03T10:40:14Z (agent-builder-2-081313) done. Added
  `CONDUCTOR_URL=http://100.75.75.39:8200` to `jobs/cluster-dashboard.hcl`, updated the dashboard
  code default in `meta/dashboard/server.py`, and documented `CONDUCTOR_URL` / `GATEWAYS` in
  `meta/dashboard/README.md`. Placement remains the existing bigo-server dashboard service; no
  node/client config or Claude credentials changed.

  **Verified:** `monad validate jobs/cluster-dashboard.hcl` passed with the pre-existing
  shutdown-delay warning, `python3 -m py_compile meta/dashboard/server.py` passed, and
  `monad deploy jobs/cluster-dashboard.hcl` completed deployment `8d4c272e` successfully. New
  allocation `01698564` is running and Nomad check `cluster-dashboard` returns HTTP 200.
  `GET http://100.78.218.70:8088/api/chat/targets` now reports conductor URL
  `http://100.75.75.39:8200` with `up:true`.

  **How to use:** open the dashboard at `http://100.78.218.70:8088` and use the chat target
  `conductor`, or inspect `GET http://100.78.218.70:8088/api/chat/targets`.
