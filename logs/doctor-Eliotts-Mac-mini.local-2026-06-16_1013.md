# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_1013
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL**

## Issues

- Nomad agent is not running or not responding
  - Checked macOS LaunchAgent `monad.nomad-client` and config `/Users/e/nomad/config/client.hcl`.
  - Restarted with `launchctl kickstart -k gui/501/monad.nomad-client`.
  - Verified local client health: `http://100.113.252.45:4646/v1/agent/health` returns ok; new PID 72350.
  - Cluster commands still fail because servers have no leader: `V1410-1` alive, `claudebox` failed.

## Warnings

- Git has       10 uncommitted changes
- Tailscale/server reachability to `100.75.75.39` is ok; ICMP and ports 4646/4647 reachable.
- Disk is at 90%; repo logs are only 1.0M, `/Users/e/nomad/logs` 28M, `/tmp` empty, Docker daemon unavailable for prune.
Restarted the local Nomad LaunchAgent `monad.nomad-client` using `/Users/e/nomad/config/client.hcl`. The local client is now responding: `agent/health` returns `ok`, and it is running as PID `72350`.

Remaining blocker is cluster-side: `100.75.75.39` is reachable, but Nomad has no leader because `V1410-1` is alive/non-leader and `claudebox` is failed. I also checked disk cleanup targets: repo logs are small, `/tmp` is empty, and `docker` is not installed/available.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-16_1013.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_1013.md).