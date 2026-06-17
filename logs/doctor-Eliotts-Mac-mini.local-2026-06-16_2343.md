# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_2343
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       30 uncommitted changes

## Actions

- Found local Nomad client running as `monad.nomad-client` with config `/Users/e/nomad/config/client.hcl`.
- Verified local client responds on configured Tailscale bind address `http://100.113.252.45:4646`; `127.0.0.1:4646` is not bound by this config.
- Checked Tailscale: server `100.75.75.39` reachable; `claudebox` and `oraclebox1` timed out.
- Checked Nomad server members: `V1410-1` alive, `claudebox` failed, no cluster leader; local client heartbeat stale because quorum/leader is down.
- Tried SSH/Tailscale SSH path to `V1410-1`; accepted the host key, then blocked by Tailscale SSH interactive auth.
- Claimed `health:v1410-1`, then marked blocked: quorum loss needs another voter restored or deliberate Raft recovery on `V1410-1`.
- Emitted follow-up infra task `t-0157`.

## Result

Local Nomad agent is running and responding on its configured address. The remaining outage is upstream Nomad quorum loss / no leader, not a local Mac client restart issue.
Updated [the doctor log](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_2343.md).

Result: the Mac’s local Nomad client is running and responds on its configured Tailscale address `100.113.252.45:4646`; it is not bound to `127.0.0.1`. The actual failure is upstream: `V1410-1` is reachable but Nomad has no leader, `claudebox` is failed/unreachable, and `oraclebox1` is unreachable, so quorum is lost.

I claimed `health:v1410-1`, marked it blocked due quorum loss, and emitted follow-up infra task `t-0157`. SSH to `V1410-1` hit Tailscale interactive auth, so I did not perform a blind server restart.