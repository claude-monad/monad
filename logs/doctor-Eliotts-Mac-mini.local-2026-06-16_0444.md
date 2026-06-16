# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_0444
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has        5 uncommitted changes

## Actions

- 2026-06-16T04:48:16-0600 Checked `/Users/e/nomad/config/client.hcl`; Tailscale bind IP matched this host (`100.113.252.45`).
- Restarted local Nomad client with `launchctl kickstart -k gui/$(id -u)/monad.nomad-client`.
- Verified new Nomad client PID `70501`; local API responds at `http://100.113.252.45:4646` and reports 4 allocations.
- Server `100.75.75.39` is reachable, but Nomad still returns `No cluster leader`; `nomad server members` shows `V1410-1` alive and `claudebox` failed, so remaining issue is server quorum, not this local client.
- Checked disk/log cleanup path; data volume is at 90% with ~20GiB free, repo logs are small, `/tmp` had no obvious old entries, and Docker CLI is not installed.
Restarted the local Nomad client via launchd and verified it is back up:

- New client PID: `70501`
- Local API responds at `http://100.113.252.45:4646`
- Agent reports 4 allocations

The remaining failure is upstream: `100.75.75.39` is reachable, but Nomad returns `No cluster leader`. `nomad server members` shows `V1410-1` alive but not leader, and `claudebox` failed, so this is a server quorum issue rather than this Mac mini’s local client.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-16_0444.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_0444.md).