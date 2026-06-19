# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-19_0441
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has        6 uncommitted changes

## Actions

- Checked macOS Nomad config: `/Users/e/nomad/config/client.hcl` exists and advertises current Tailscale IP `100.113.252.45`.
- Restarted local Nomad LaunchAgent: `monad.nomad-client` via `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified local client API healthy after restart: `/v1/agent/health?type=client` returned OK; fresh client PID `76502`.
- Verified Tailscale/server path: local Tailscale is up, `100.75.75.39:4647` is reachable.
- Checked git conflicts: none found. Left existing uncommitted files untouched.
- Checked disk cleanup targets: filesystem is at 90%, but repo logs are 1.2M, `/Users/e/nomad/logs` is 36M, `/tmp` is empty, and no old log files were found; `docker` is not installed in this shell.

## Remaining

- Nomad server API is reachable but cluster has no leader. `nomad server members` shows `V1410-1` alive and `claudebox` failed in a two-voter raft set, so this needs server/quorum repair outside this local client restart.
Restarted the local Nomad LaunchAgent `monad.nomad-client`. The local agent API is now healthy: `{"client":{"message":"ok","ok":true}}`.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-19_0441.md](/Users/e/nomad/data/alloc/230a4756-d01e-429c-dcb6-fb7ff425c393/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-19_0441.md).

Residual issue: the Nomad server is reachable, but the cluster has no leader. `nomad server members` shows `V1410-1` alive and `claudebox` failed in a two-voter raft set, so this is now a server/quorum repair issue rather than a local client process issue.