# Node Doctor Report: claudebox

**Time:** 2026-07-27_1235
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Warnings

- Git has 2 uncommitted changes

## Actions

- Restarted local `tailscaled`; service is active.
- Checked local Nomad: it is running from `/home/claude/nomad/server.hcl` and listening on `100.87.219.108:4646-4648`; no restart was needed.
- Retested Tailscale and TCP port 4646; server is still unreachable.
- Server `v1410-1` is offline (last seen 24 days ago) and its Tailscale node key is expired.
- Local Nomad is isolated in Raft candidate state with no cluster leader because the remote voter cannot be reached.
- Disk usage is 9%; no cleanup was needed. No Git merge conflicts were present.
- Remote action required: renew/re-authenticate Tailscale and restart/check Nomad on `v1410-1`.
Local recovery was attempted:

- Restarted `tailscaled`; it is active.
- Confirmed local Nomad is running and its configuration is valid.
- Remote `v1410-1` remains offline with an expired Tailscale key, so `100.75.75.39:4646` is still unreachable.
- Disk and Git conflicts require no action.

Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-27_1235.md). Remote Tailscale re-authentication is required on `v1410-1`.