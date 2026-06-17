# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_0403
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTORED**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has        4 uncommitted changes

## Actions

- Checked macOS LaunchAgent: `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked client config: `/Users/e/nomad/config/client.hcl`; Tailscale IP matches `100.113.252.45`.
- Restarted local Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`; new PID `17575`.
- Verified local agent API: `http://100.113.252.45:4646/v1/agent/health` returned client ok.
- Verified server `100.75.75.39:4646` is reachable, but Nomad servers still report `No cluster leader` with `claudebox` failed/offline.
- Disk is high but not full: data volume at 90%; no cleanup performed for this issue.
Local Nomad client was restored. I checked the LaunchAgent and config, restarted `monad.nomad-client` with launchd, and verified the local agent API returns healthy:

`{"client":{"message":"ok","ok":true}}`

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-16_0403.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_0403.md)

Remaining issue is server-side: `100.75.75.39:4646` is reachable, but Nomad still reports `No cluster leader`; `claudebox` is failed/offline. No git conflicts were present, so I did not commit anything.