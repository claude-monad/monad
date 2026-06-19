# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-18_1816
**Updated:** 2026-06-18 18:19 MDT
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION - upstream Nomad quorum/leader issue**

## Actions

- Checked macOS launchd config: `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Verified Nomad client service is running as PID 70563 with `/Users/e/nomad/config/client.hcl`.
- Verified local Nomad API responds on `127.0.0.1:4646`; did not restart because the local agent is healthy.
- Verified Tailscale IP is `100.113.252.45`, matching the Nomad advertise address.
- Verified server `100.75.75.39` is reachable over Tailscale.
- Nomad server state still unhealthy: `V1410-1` alive, `claudebox` failed, no cluster leader.
- Checked cleanup paths: repo logs 1.2M, `/tmp` empty, Docker not installed; no safe cleanup performed.
- Checked Git conflicts: none.

## Remaining

- Local client registration/heartbeats are blocked by upstream Nomad errors: `No cluster leader` and timeout to `100.87.219.108:4647`.
- Disk remains high at 91%, but requested cleanup locations had nothing material to remove.
Checked and updated [doctor log](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-18_1816.md).

Local Nomad is running and responding: launchd service `monad.nomad-client`, PID `70563`, config `/Users/e/nomad/config/client.hcl`. I did not restart it because the local API is healthy.

Remaining issue is upstream: `100.75.75.39` is reachable over Tailscale, but Nomad reports no cluster leader; `V1410-1` is alive and `claudebox` is failed. Disk is still 91%, but repo logs were tiny, `/tmp` was empty, and Docker is not installed, so there was no safe cleanup target. No Git conflicts found.