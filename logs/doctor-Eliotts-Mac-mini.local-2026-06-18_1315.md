# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-18_1315
**Node:** Eliotts-Mac-mini.local

**Status: LOCAL NOMAD RESTARTED; CLUSTER STILL NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       72 uncommitted changes

## Actions

- Checked macOS launch agent `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked Nomad config `/Users/e/nomad/config/client.hcl`; advertise IP matches Tailscale IP `100.113.252.45`.
- Restarted Nomad with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified local Nomad process is running and `http://127.0.0.1:4646/v1/agent/health` returns OK.
- Checked disk cleanup targets: repo logs are 1.2M, `/tmp` is empty, Docker CLI is absent.

## Remaining

- Local agent cannot register because Nomad servers have no leader.
- `100.75.75.39` is reachable over Tailscale but reports `No cluster leader`.
- `100.87.219.108` times out over Tailscale and is failed in `nomad server members`.
Restarted the local Nomad launch agent and verified it is running:

- `monad.nomad-client` is active as PID `11386`
- Local health endpoint returns OK: `http://127.0.0.1:4646/v1/agent/health`
- Config checked at `/Users/e/nomad/config/client.hcl`
- LaunchAgent checked at `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`

Updated the doctor log here: [doctor-Eliotts-Mac-mini.local-2026-06-18_1315.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-18_1315.md)

Remaining blocker: the local agent is healthy, but the Nomad cluster still has no leader. `100.75.75.39` is reachable but returns `No cluster leader`; `100.87.219.108` times out and is failed in `nomad server members`.