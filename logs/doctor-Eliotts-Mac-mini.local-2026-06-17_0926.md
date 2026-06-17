# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_0926
**Node:** Eliotts-Mac-mini.local

**Status: LOCAL NOMAD FIXED; CLUSTER NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 3.69%/day — will hit 95% in ~1.1 days

## Warnings

- Git has       41 uncommitted changes
- Disk usage is 91%

## Actions

- Checked `~/Library/LaunchAgents/monad.nomad-client.plist`; LaunchAgent was loaded as PID 8045.
- Found Nomad listening only on `100.113.252.45:4646`; `127.0.0.1:4646` was refused.
- Updated `/Users/e/nomad/config/client.hcl` to `bind_addr = "0.0.0.0"` while keeping Tailscale advertise addresses.
- Validated config with `nomad config validate /Users/e/nomad/config/client.hcl`.
- Restarted with `launchctl kickstart -k gui/501/monad.nomad-client`; new PID 56167.
- Verified `nomad agent-info` works on both `127.0.0.1:4646` and `100.113.252.45:4646`.
- Tailscale/server reachability: `100.75.75.39:4646` reachable, but Nomad reports `No cluster leader`; `claudebox` server member is failed.
- Disk cleanup: repo logs 1.2M, `/Users/e/nomad/logs` 31M, `/tmp` 0B; Docker CLI unavailable, no prune run.
- Git: no merge-conflict entries in `git status`; existing uncommitted changes left untouched.
Local Nomad responsiveness is fixed. I updated [client.hcl](/Users/e/nomad/config/client.hcl) to bind on `0.0.0.0`, validated the config, and restarted `monad.nomad-client` via `launchctl`. It is now running as PID `56167`, and `nomad agent-info` works on `127.0.0.1:4646`.

Updated the doctor log here: [doctor log](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_0926.md).

Remaining issue noted in the log: server `100.75.75.39` is reachable, but Nomad reports `No cluster leader`; `claudebox` is failed. Disk cleanup had nothing meaningful to remove, and Docker CLI is unavailable.