# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-19_0908
**Node:** Eliotts-Mac-mini.local

**Status: LOCAL NOMAD FIXED; CLUSTER NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding
  - Checked `/Users/e/nomad/config/client.hcl`; advertise IP matches local Tailscale IP `100.113.252.45`.
  - Local agent was running but stale: heartbeat was about `1h53m` old.
  - Restarted `monad.nomad-client` with `launchctl kickstart -k gui/501/monad.nomad-client`.
  - Verified new PID `48187`; local health endpoint returns `{"client":{"message":"ok","ok":true}}`.
  - Post-restart heartbeat refreshed to about `1m`.
  - `nomad status` still fails with `500 No cluster leader`; `nomad server members` shows only `V1410-1` alive and not leader.
  - Tailscale/server check: `100.75.75.39` reachable on ports `4646`, `4647`, `4648`; `claudebox`/`100.87.219.108` is offline and ping timed out.

## Warnings

- Git has 7 uncommitted changes; no conflict state detected, left unchanged.
- Disk is tight at 90%, but cleanup targets were small (`logs` 1.2M, `/Users/e/nomad/logs` 36M, `/tmp` 0B); no cleanup performed.
Restarted the local Nomad LaunchAgent:

`launchctl kickstart -k gui/501/monad.nomad-client`

Result: local Nomad is running again with PID `48187`, and `http://127.0.0.1:4646/v1/agent/health` returns OK.

Remaining issue is upstream cluster quorum: `nomad status` still returns `500 No cluster leader`. `100.75.75.39` is reachable on Nomad ports, but `claudebox` / `100.87.219.108` is offline and timed out, leaving only `V1410-1` visible as alive and not leader.

Updated the doctor log at [logs/doctor-Eliotts-Mac-mini.local-2026-06-19_0908.md](/Users/e/nomad/data/alloc/230a4756-d01e-429c-dcb6-fb7ff425c393/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-19_0908.md).