# Node Doctor Report: claudebox

**Time:** 2026-07-30_1719
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Actions

- Confirmed claudebox Nomad is running from `/home/claude/nomad/server.hcl` and listening on `100.87.219.108:4646-4648`.
- Restarted local `tailscaled`; it returned active with working UDP/DERP connectivity.
- Retested `100.75.75.39` with `tailscale ping` and the Nomad HTTP endpoint.

## Result

- Still unreachable: Tailscale reports `v1410-1` offline for 28 days and `peer's node key has expired`; Nomad HTTP times out.
- Requires console/provider access on `v1410-1` to re-authenticate Tailscale, then restart/verify Nomad. Do not bootstrap or alter Raft peers.

## Warnings

- Git has 2 uncommitted changes
Local services are healthy, but the remote Nomad server remains unreachable.

- Restarted and verified `tailscaled`.
- Verified local Nomad returns HTTP 200.
- `v1410-1` is offline with an expired Tailscale node key; console/provider access is required to re-authenticate it and restart Nomad.
- Updated the [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-30_1719.md).