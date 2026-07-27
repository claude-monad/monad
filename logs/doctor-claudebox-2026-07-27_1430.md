# Node Doctor Report: claudebox

**Time:** 2026-07-27_1430
**Node:** claudebox

**Status: REMOTE ATTENTION REQUIRED**

## Issues

- Nomad server `100.75.75.39:4646` remains unreachable.

## Actions

- Confirmed local `tailscaled` was active and Tailscale network checks passed.
- Restarted `tailscaled`; it returned active and claudebox remained authenticated.
- Retested Tailscale ping and TCP/4646. `v1410-1` is offline (last seen 24 days ago) and its node key has expired.
- Remote console access is required to re-authenticate/start Tailscale on `v1410-1`, then verify Nomad.

## Warnings

- Git has 1 uncommitted changes
Local Tailscale was restarted and is healthy, but Nomad remains unreachable because `v1410-1` is offline and its Tailscale node key has expired. Remote console access is required to re-authenticate that server.

Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-27_1430.md).