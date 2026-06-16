# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_1742
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL AGENT RESTORED**

## Issues

- Nomad agent is not running or not responding

## Actions

- Checked macOS launchd config: `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked Nomad client config: `/Users/e/nomad/config/client.hcl`; bind/advertise IP matches Tailscale IP `100.113.252.45`.
- Restarted launchd job `monad.nomad-client`; new Nomad PID is `18498`.
- Verified local client health: `http://100.113.252.45:4646/v1/agent/health` returns `{"client":{"message":"ok","ok":true}}`.
- Verified server network path: `100.75.75.39:4646` accepts TCP and ping has 0% packet loss.
- No git conflicts found; no conflict commit made.
- Disk cleanup targets checked: repo logs about 1 MB, `/tmp` empty, Docker CLI not installed.

## Remaining

- Cluster API still returns `No cluster leader`; local client log also shows RPC failures to `100.87.219.108:4647`.

## Predictions

- ⚠ Disk usage trending up at 4.44%/day — will hit 95% in ~0.7 days

## Warnings

- Git has       23 uncommitted changes
- Disk usage is 92%
Restarted the local Nomad launchd job `monad.nomad-client`. It is now running as PID `18498` and the client health endpoint returns OK on `http://100.113.252.45:4646`.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-16_1742.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_1742.md:1).

Remaining issue: the Nomad server path is reachable, but the cluster API still returns `No cluster leader`, and the client log shows RPC failures to `100.87.219.108:4647`. No git conflicts were present.