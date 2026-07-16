# Node Doctor Report: claudebox

**Time:** 2026-07-16_0354
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Actions

- Confirmed the local Nomad agent is running (PID 1490) and listening on 100.87.219.108:4646-4648 with `/home/claude/nomad/server.hcl`.
- Confirmed `tailscaled` is active, refreshed the local connection with `tailscale up`, and verified connectivity to another peer (bigo-server, 1 ms).
- Retested 100.75.75.39: its Tailscale node `v1410-1` is offline (last seen 13 days ago) and reports `peer's node key has expired`; port 4646 still times out. Recovery requires re-authenticating/restarting Tailscale on `v1410-1`.
- Local disk is healthy (7% used). Git has uncommitted changes but no reported merge conflicts; left existing work untouched.

## Warnings

- Git has 5 uncommitted changes
- Nomad has no reachable configured server/quorum while `v1410-1` and the alternate `oraclebox1` are offline.
Claudebox-side services are healthy:

- Local Nomad is running and listening.
- Tailscale was refreshed and works with other peers.
- `100.75.75.39` remains offline with an expired Tailscale node key; recovery must occur on `v1410-1`.
- Disk is healthy and no Git conflicts were found.

Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-16_0354.md).