# Node Doctor Report: claudebox

**Time:** 2026-07-28_2300
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Work performed

- Confirmed `100.75.75.39:4646` is unreachable.
- Confirmed local `tailscaled` was active, restarted it, and retested.
- Tailscale reports `v1410-1` offline for 26 days; `tailscale ping` reports its node key has expired.
- Confirmed the local Nomad agent is running from `/home/claude/nomad/server.hcl` and listening on `100.87.219.108:4646-4648`; it currently has no Raft leader.
- Disk is healthy at 9%; no cleanup or Docker prune was needed.
- No Git conflicts were present; existing log/metrics changes were left intact.

## Remaining action

- On `v1410-1`, reconnect/re-authenticate Tailscale and restart Nomad if needed, then verify `100.75.75.39:4646` and Raft leadership.
Tailscale was restarted and remains active, but `v1410-1` is still offline because its Tailscale node key expired. It requires console-side reauthentication before Nomad quorum can recover.

Disk is healthy; no Git conflicts or cleanup needed. Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-28_2300.md).