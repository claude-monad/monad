# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_0856
**Node:** Eliotts-Mac-mini.local
**Status:** PARTIAL - local client restored, cluster leader still unavailable

## Actions

- Checked macOS launchd config: `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked Nomad client config: `/Users/e/nomad/config/client.hcl`; Tailscale IP `100.113.252.45` matched `tailscale ip -4`.
- Restarted local Nomad client with `launchctl kickstart -k gui/$(id -u)/monad.nomad-client`.
- Verified new agent PID `75714` and listener `100.113.252.45:4646`.
- Verified local client health: `{"client":{"message":"ok","ok":true}}`.

## Remaining

- Nomad server `100.75.75.39` is reachable on RPC `4647`, but CLI/API reports `No cluster leader`.
- Git has uncommitted log/state changes, but no merge-conflict paths were reported.
- Disk is at 90% on `/System/Volumes/Data`; repo logs are small, so no cleanup was performed for this Nomad-agent-only alert.
Restarted the local Nomad client via `launchctl`. It is now running as PID `75714`, listening on `100.113.252.45:4646`, and `/v1/agent/health` returns OK.

Updated [doctor-Eliotts-Mac-mini.local-2026-06-16_0856.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_0856.md).

Remaining issue: server `100.75.75.39` is reachable on RPC `4647`, but Nomad reports `No cluster leader`, so the unresolved problem is cluster/server-side rather than this local client process.