# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_0242
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTORED**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       37 uncommitted changes

## Actions

- Checked macOS LaunchAgent `/Users/e/Library/LaunchAgents/monad.nomad-client.plist` and config `/Users/e/nomad/config/client.hcl`; config matches Tailscale IP `100.113.252.45`.
- Restarted Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`; PID changed from `16205` to `69017`.
- Verified local client API responds at `http://100.113.252.45:4646`; heartbeat refreshed to ~10s after restart.
- Checked Tailscale: primary server `100.75.75.39` replies, but peer server `100.87.219.108` times out.
- Remaining issue: Nomad servers report `No cluster leader`; `V1410-1` is alive but `claudebox` is failed, so this is upstream quorum/peer recovery rather than a local client process failure.
Local Nomad client was restarted and is responsive again.

I updated [doctor-Eliotts-Mac-mini.local-2026-06-17_0242.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_0242.md) with the actions taken.

Key result: `monad.nomad-client` is running under LaunchAgent with PID `69017`, and the local API responds at `http://100.113.252.45:4646`.

Remaining blocker: the Nomad servers still report `No cluster leader`. `100.75.75.39` is reachable, but peer server `100.87.219.108` times out over Tailscale, so quorum/peer recovery is still needed upstream.