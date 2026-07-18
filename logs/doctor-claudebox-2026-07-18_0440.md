# Node Doctor Report: claudebox

**Time:** 2026-07-18_0440
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Warnings

- Git has 3 uncommitted changes

## Doctor actions

- Restarted `tailscaled`; claudebox reconnected successfully as `100.87.219.108`.
- Retested `100.75.75.39:4646`; it remains unreachable. `tailscale ping` reports `peer's node key has expired`, and `v1410-1` is offline (last seen 15 days ago).
- Verified the local Nomad agent is running from `/home/claude/nomad/server.hcl`, listening on `100.87.219.108:4646-4648`, and its local API responds; no cluster leader is currently available.
- Verified disk usage is 8%, so no cleanup was needed. Git has no conflicts, so no conflict commit was made; existing worktree changes were preserved.

**Result: PARTIAL — local Tailscale and Nomad are healthy; re-authenticate Tailscale on `v1410-1`, then verify/restart Nomad there.**
Partial recovery completed:

- Restarted Tailscale; `claudebox` is connected.
- Confirmed local Nomad is running and healthy.
- Disk is 8% full; no cleanup needed.
- No Git conflicts found; existing changes preserved.
- `v1410-1` remains unreachable because its Tailscale node key expired. It requires on-host Tailscale re-authentication, followed by a Nomad check/restart.

Updated the [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-18_0440.md).