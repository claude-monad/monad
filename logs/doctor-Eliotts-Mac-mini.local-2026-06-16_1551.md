# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_1551
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTARTED**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 2.03%/day — will hit 95% in ~2.0 days

## Warnings

- Git has       19 uncommitted changes
- Disk usage is 91%

## Actions

- Checked macOS launchd service `monad.nomad-client` and config `/Users/e/nomad/config/client.hcl`.
- Confirmed Tailscale IP is `100.113.252.45`, matching Nomad bind/advertise config.
- Restarted local Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified new Nomad PID `80891` is running and listening on `100.113.252.45:4646`; `/v1/agent/self` responds.
- Remaining blocker: client registration still fails because upstream Nomad reports `rpc error: No cluster leader`; `100.75.75.39` is reachable in Tailscale but `/v1/status/leader` timed out.
Done. Local Nomad was running but bound to Tailscale, not `127.0.0.1`. I restarted the launchd job anyway:

`launchctl kickstart -k gui/501/monad.nomad-client`

Verified afterward:
- Nomad PID `80891` is running.
- It is listening on `100.113.252.45:4646`.
- `/v1/agent/self` responds.

Remaining blocker is upstream: Nomad RPC still returns `No cluster leader`, and `100.75.75.39` is reachable via Tailscale but `/v1/status/leader` timed out. I logged that in [doctor-Eliotts-Mac-mini.local-2026-06-16_1551.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_1551.md).