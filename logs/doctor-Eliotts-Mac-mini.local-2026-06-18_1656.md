# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-18_1656
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       79 uncommitted changes
- Disk usage is 91%

## Actions

- Checked macOS LaunchAgent `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked Nomad config `/Users/e/nomad/config/client.hcl`; advertised Tailscale IP matches current `100.113.252.45`.
- Restarted local Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`; new agent PID `70563`.
- Verified local Nomad API health: `{"client":{"message":"ok","ok":true}}`; heartbeat dropped from stale hours to under 1 minute.
- Checked Git conflicts: no unmerged files; left unrelated dirty worktree untouched.
- Checked disk cleanup targets: repo `logs/` 1.2M, `/tmp` 0B, Docker not installed; no useful safe cleanup performed.
- Checked server reachability: `100.75.75.39:4647` reachable, Tailscale pong via DERP.

## Remaining

- Cluster queries still fail with `No cluster leader`; local client is running/responding, remaining issue is upstream Nomad server/quorum.
Handled.

Local Nomad is now running under `monad.nomad-client` as PID `70563`, and `http://127.0.0.1:4646/v1/agent/health` returns `ok`. I checked the macOS LaunchAgent and `/Users/e/nomad/config/client.hcl`, then restarted the client with `launchctl kickstart -k gui/501/monad.nomad-client`.

I also updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-18_1656.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-18_1656.md).

Remaining issue: local Nomad is healthy, but cluster queries still fail with `No cluster leader`. Server `100.75.75.39:4647` is reachable, so this looks like upstream Nomad quorum/server state rather than a local agent failure.