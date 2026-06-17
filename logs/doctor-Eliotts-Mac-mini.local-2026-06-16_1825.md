# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_1825
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL FIX - NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 4.72%/day — will hit 95% in ~0.6 days

## Warnings

- Git has       25 uncommitted changes
- Disk usage is 92%

## Actions Taken

- Checked macOS launchd job `monad.nomad-client`; Nomad client was running from `/Users/e/nomad/config/client.hcl`.
- Verified Tailscale IP `100.113.252.45` matches Nomad bind/advertise config.
- Restarted local Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`; new PID `68659`.
- Verified Nomad is listening on `100.113.252.45:4646` and `nomad agent-info` responds.

## Remaining Issue

- Cluster has no Nomad leader: `V1410-1` is alive, `claudebox` is failed, and server queries return `No cluster leader`.
Local Nomad client fix is done. I restarted `monad.nomad-client` via launchd; it is now running as PID `68659` and listening on `100.113.252.45:4646`. `nomad agent-info` responds.

Updated the doctor report here: [doctor-Eliotts-Mac-mini.local-2026-06-16_1825.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_1825.md)

Remaining blocker: the Nomad server side has no cluster leader. `V1410-1` is alive, `claudebox` is failed, and server queries return `No cluster leader`, so cluster-level node status may still fail until quorum is restored.