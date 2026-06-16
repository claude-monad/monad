# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_0814
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       10 uncommitted changes

## Actions

- Checked macOS launchd config: `/Users/e/Library/LaunchAgents/monad.nomad-client.plist` runs `/Users/e/nomad/start.sh`.
- Verified Nomad config at `/Users/e/nomad/config/client.hcl`; Tailscale IP is `100.113.252.45` and matches `bind_addr`.
- Restarted client with `launchctl kickstart -k gui/501/monad.nomad-client`; new Nomad PID `24515`.
- Local agent health now OK at `http://100.113.252.45:4646/v1/agent/health`.

## Remaining

- Cluster/server side still unhealthy: `nomad server members` shows `V1410-1` alive but no leader, `claudebox` failed; `100.75.75.39:4646/v1/status/leader` timed out.
- Tailscale is up locally; `v1410-1` is active/direct at `100.75.75.39`, while `claudebox` is offline in Tailscale.
- Disk at 90%; requested log dirs are small (`logs` 1.0M, `/Users/e/nomad/logs` 28M) and `/tmp` is empty, so no cleanup performed.
Nomad client was restarted via launchd (`monad.nomad-client`) and is now responding:

`http://100.113.252.45:4646/v1/agent/health` -> `{"client":{"message":"ok","ok":true}}`

I updated the doctor log here: [doctor-Eliotts-Mac-mini.local-2026-06-16_0814.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_0814.md)

Remaining issue is cluster-side: Nomad reports no server leader, `v1410-1` is reachable over Tailscale, and `claudebox` is offline/failed. Local agent is fixed; server quorum still needs attention.