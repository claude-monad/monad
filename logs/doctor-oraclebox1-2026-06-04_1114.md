# Node Doctor Report: oraclebox1

**Time:** 2026-06-04_1114
**Node:** oraclebox1

**Status: PARTIAL - REMOTE SERVER STILL UNREACHABLE**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646
- Nomad agent is not running or not responding

## Warnings

- Git has 2 uncommitted changes

## Actions Taken

- Checked `/etc/nomad.d`; `nomad config validate /etc/nomad.d` reports configuration is valid.
- Confirmed local Nomad was running but in Raft candidate/no-leader state.
- Restarted `tailscaled`; local Tailscale IP remains `100.125.210.126`.
- Retested `100.75.75.39:4646`; TCP and HTTP still time out, and `tailscale ping 100.75.75.39` gets no reply.
- Restarted `nomad`; service is active and local API responds at `100.125.210.126:4646`.
- Nomad still cannot form quorum because peers `100.75.75.39:4647` and `100.87.219.108:4647` time out.
- Checked git conflicts: none found.
- Checked disk: `/` is 75% used, so no disk cleanup/prune was performed.

## Remaining

- Bring `v1410-1` / `100.75.75.39` back online on Tailscale, or restore Nomad peer quorum from another server.
Updated [doctor-oraclebox1-2026-06-04_1114.md](/home/ubuntu/monad/logs/doctor-oraclebox1-2026-06-04_1114.md).

What I did:
- Validated `/etc/nomad.d`; config is valid.
- Restarted `tailscaled`.
- Restarted `nomad`.
- Verified `nomad` and `tailscaled` are active.
- Verified local Nomad API responds at `100.125.210.126:4646`.
- Checked git conflicts: none.
- Checked disk: `/` is 75% used, no cleanup needed.

Remaining issue: `100.75.75.39` is still unreachable. `tailscale ping` gets no reply, and TCP/HTTP to `100.75.75.39:4646` time out. Nomad is running locally but still cannot form quorum because remote peers are timing out.