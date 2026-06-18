# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_2018
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTARTED**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 2.52%/day — will hit 95% in ~1.2 days

## Warnings

- Git has       60 uncommitted changes
- Disk usage is 92%

## Actions

- Checked macOS LaunchAgent `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Confirmed config `/Users/e/nomad/config/client.hcl` advertises Tailscale IP `100.113.252.45` and servers `100.75.75.39:4647`, `100.87.219.108:4647`.
- Restarted local Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified LaunchAgent running after restart as PID `50391`; local client health endpoint returns OK and `nomad agent-info` responds.
- Verified `100.75.75.39:4646/4647` reachable over Tailscale.
- Checked Git for unmerged conflict files; none found.

## Remaining

- Nomad server RPC still reports `No cluster leader`; `100.87.219.108:4647` times out. Local client is running but cannot fully register until server quorum/leader is restored.
Handled the local node fix.

Restarted `monad.nomad-client` via `launchctl kickstart -k gui/501/monad.nomad-client`. Nomad is now running as PID `50391`; local health returns OK and `nomad agent-info` responds.

Remaining issue is upstream: `100.75.75.39` is reachable, but Nomad RPC still reports `No cluster leader`, and `100.87.219.108:4647` times out. The client cannot fully register until server quorum/leader is restored.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-17_2018.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_2018.md).