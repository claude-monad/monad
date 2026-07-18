# Node Doctor Report: claudebox

**Time:** 2026-07-18_0033
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Warnings

- Git has 2 uncommitted changes

## Actions

- Confirmed local Tailscale was connected and restarted `tailscaled` successfully.
- Confirmed the local script-managed Nomad agent is running and listening on `100.87.219.108:4646` (there is no `nomad.service`).
- Retested `100.75.75.39:4646`; it still times out.
- `tailscale ping` reports the remote peer's node key has expired; re-authentication is required on `v1410-1`.
- Checked Git: no merge conflicts found; existing uncommitted changes were left intact.
Tailscale was restarted and is active, but `100.75.75.39:4646` remains unreachable. The remote peer `v1410-1` has an expired Tailscale node key and must be re-authenticated on that host.

Local Nomad is running. No Git conflicts were found. Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-18_0033.md).