# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_1234
**Node:** Eliotts-Mac-mini.local

**Status: LOCAL NOMAD RESTORED; CLUSTER NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 3.56%/day — will hit 95% in ~0.8 days

## Warnings

- Git has       48 uncommitted changes
- Disk usage is 92%

## Actions Taken

- Checked macOS LaunchAgent config: `~/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked Nomad client config: `/Users/e/nomad/config/client.hcl`.
- Found Nomad client running but cluster queries failed with `No cluster leader`.
- Restarted local Nomad client with `launchctl kickstart -k gui/$(id -u)/monad.nomad-client`.
- Verified new Nomad PID `79105` and local health: `{"client":{"message":"ok","ok":true}}`.
- Verified Tailscale can reach server `100.75.75.39` (`tailscale ping` OK).
- Server API still returns `500 No cluster leader`; this is not a local client-start failure.
- Disk check: filesystem 92% used, repo logs 1.2M, `/Users/e/nomad/logs` 31M, `/tmp` empty; no useful log/tmp cleanup target found.
Local Nomad client is restored. I checked the macOS LaunchAgent and `/Users/e/nomad/config/client.hcl`, restarted `monad.nomad-client` with `launchctl kickstart -k`, and verified:

`79105  1  monad.nomad-client`  
`{"client":{"message":"ok","ok":true}}`

I updated the report here: [doctor log](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_1234.md:1).

Remaining issue: `100.75.75.39` is reachable over Tailscale, but Nomad server queries still fail with `500 No cluster leader`, so that is a cluster/server-side problem rather than this node’s local client failing to start.