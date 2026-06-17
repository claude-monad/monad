# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_0158
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       36 uncommitted changes

## Actions

- Checked `/Users/e/nomad/config/client.hcl`; `nomad config validate` passed.
- Found Nomad client launch agent `monad.nomad-client` running but stale (`last_heartbeat` ~43m).
- Restarted local Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified new Nomad client PID `16205` and local API response on `100.113.252.45:4646`.
- Checked Git conflicts: none (`git diff --name-only --diff-filter=U` empty).
- Checked disk cleanup targets: repo logs ~1.1M, `/tmp` 0B; Docker unavailable, no prune run.

## Remaining

- Cluster still has no Nomad leader: `V1410-1` (`100.75.75.39`) reachable/alive, `claudebox` (`100.87.219.108`) failed/offline in Tailscale and ping timed out.
Fixed the local Nomad agent path as far as this node can:

- Validated `/Users/e/nomad/config/client.hcl`.
- Restarted `monad.nomad-client` via `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified Nomad client is running as PID `16205` and responding on `100.113.252.45:4646`.
- Confirmed no Git conflict entries.
- Checked cleanup targets: `logs` ~1.1M, `/tmp` 0B, Docker unavailable.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-17_0158.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_0158.md).

Remaining issue: the cluster still has no Nomad leader. `100.75.75.39` is reachable/alive, but `claudebox` / `100.87.219.108` is offline in Tailscale and Nomad marks it failed.