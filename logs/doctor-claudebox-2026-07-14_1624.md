# Node Doctor Report: claudebox

**Time:** 2026-07-14_1624
**Node:** claudebox

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646

## Warnings

- Git has 14 uncommitted changes

## Doctor actions

- Confirmed claudebox Tailscale and Nomad agent are running; local Nomad API responds on `100.87.219.108:4646`.
- Restarted `tailscaled` and retested ping/API access to `100.75.75.39:4646`.
- Tailscale reports `v1410-1` offline for 12 days and `peer's node key has expired`; direct Nomad access still times out.
- Checked Git: no unmerged/conflicted paths. Disk cleanup was not required.
- Remaining action: reauthenticate/restart Tailscale on `v1410-1`, then restart/check Nomad there.
Tailscale was restarted, but `v1410-1` remains unreachable because its Tailscale node key expired and it has been offline for 12 days. Reauthentication must occur on that host before Nomad can be checked/restarted there.

Claudebox’s Nomad agent is running, disk usage is healthy at 7%, and no Git conflicts exist. Updated [doctor log](/home/claude/monad/logs/doctor-claudebox-2026-07-14_1624.md).