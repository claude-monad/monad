# Node Doctor Report: claudebox

**Time:** 2026-07-16_0437
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Warnings

- Git has 5 uncommitted changes

## Doctor actions

- Restarted `tailscaled`; claudebox reconnected and is online as `100.87.219.108`.
- Retested `100.75.75.39:4646`; still unreachable because `v1410-1` is offline and its Tailscale node key expired on 2026-07-02. Re-authentication is required on `v1410-1`.
- Verified the local Nomad agent is running from `/home/claude/nomad/server.hcl` and listening on `100.87.219.108:4646-4648`; its health endpoint returns 500 while no cluster leader is reachable.
- Verified disk usage is 7%; no cleanup needed. Git has no conflicts, so no conflict commit was made.

**Result: PARTIAL — local services recovered; remote Nomad server requires on-node Tailscale re-authentication.**
Local recovery completed, but the Nomad server remains unreachable:

- Restarted Tailscale; `claudebox` is online.
- Local Nomad is running and listening correctly.
- `v1410-1` remains offline because its Tailscale key expired July 2; it requires on-node re-authentication.
- Disk usage is 7%; no cleanup needed.
- No Git conflicts found.

Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-16_0437.md).