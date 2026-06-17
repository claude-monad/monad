# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_1043
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTARTED; CLUSTER HAS NO LEADER**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 1.85%/day — will hit 95% in ~2.2 days

## Warnings

- Git has       45 uncommitted changes
- Disk usage is 91%

## Doctor Actions

- Checked `/Users/e/nomad/config/client.hcl`; Tailscale advertise IP `100.113.252.45` matches `tailscale ip -4`.
- Found `monad.nomad-client` running but stale/unregistered; restarted with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified local Nomad API responds on `127.0.0.1:4646`; new agent pid `48423`, 4 allocations restored.
- Checked Tailscale: `100.75.75.39` reachable, but peer server `100.87.219.108` times out.
- `nomad server members` shows `V1410-1` alive, `claudebox` failed, and `No cluster leader`; remaining issue is cluster quorum/leader loss, not local client config.
- Disk checked: `/System/Volumes/Data` at 91%; repo logs are small, `/tmp` empty, Docker CLI unavailable, so no cleanup performed.
Done. I checked `/Users/e/nomad/config/client.hcl`, confirmed the Tailscale advertise IP is correct, restarted the local Nomad LaunchAgent `monad.nomad-client`, and verified the local agent API is responding with pid `48423`.

Remaining blocker: the Nomad cluster has no leader. `100.75.75.39` is reachable, but `100.87.219.108` times out, and `nomad server members` reports `claudebox` failed.

Updated the doctor log here: [doctor-Eliotts-Mac-mini.local-2026-06-17_1043.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_1043.md).