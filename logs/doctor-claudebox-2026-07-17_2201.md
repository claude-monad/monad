# Node Doctor Report: claudebox

**Time:** 2026-07-17_2201
**Node:** claudebox

**Status: NEEDS REMOTE ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Actions

- Verified local `tailscaled` was running, restarted it, and confirmed a healthy local backend.
- Retested Tailscale and TCP/4646; the server remains unreachable because peer `v1410-1` is offline and its Tailscale node key has expired (last seen 15 days ago).
- Confirmed disk usage is healthy (8% used); no cleanup was needed.
- Confirmed there are no Git conflicts. Existing unrelated working-tree changes were left untouched.
- No local `nomad.service` exists on claudebox; Nomad must be restored/re-authenticated on `v1410-1`, then restarted there if needed.

## Warnings

- Git has 2 uncommitted changes
Tailscale was restarted locally and is healthy, but Nomad remains unreachable because remote peer `v1410-1` is offline with an expired Tailscale key. It requires re-authentication on that server.

No disk cleanup was needed, and no Git conflicts exist. Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-17_2201.md).