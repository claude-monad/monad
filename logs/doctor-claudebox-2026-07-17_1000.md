# Node Doctor Report: claudebox

**Time:** 2026-07-17_1000
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646 (blocked on remote host recovery)

## Actions

- Restarted local `tailscaled`; claudebox reconnected normally.
- Confirmed `v1410-1` (100.75.75.39) is offline and its Tailscale node key has expired; ping and Nomad HTTP still time out.
- Confirmed the local Nomad 2.0.2 server is running and listening on 100.87.219.108:4646 with the expected join config.
- Local Nomad remains Candidate/no leader because only claudebox is reachable in the committed two-voter set. Per cluster recovery policy, did not perform unsafe single-voter Raft surgery.

## Required follow-up

- Re-authenticate Tailscale on `v1410-1` and restart/verify Nomad there, or restore and rejoin `oraclebox1`; then confirm leader election.

## Warnings

- Git has 2 uncommitted changes
Tailscale on `claudebox` was restarted successfully, and local Nomad is healthy and listening. The remote server remains unreachable because `v1410-1` is offline with an expired Tailscale key, leaving Nomad without quorum.

Documented in [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-17_1000.md). Recovery requires on-host Tailscale re-authentication on `v1410-1`, or restoring `oraclebox1`.