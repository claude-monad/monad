# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-19_1102
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTARTED**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has        8 uncommitted changes
- Disk usage is 91%

## Actions

- Checked macOS launchd service `gui/501/monad.nomad-client`; config is `/Users/e/nomad/config/client.hcl`.
- Verified current Tailscale IP is `100.113.252.45` and config already advertises that IP.
- Restarted Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified new Nomad agent PID `79153`; local health is OK on `127.0.0.1:4646` and `100.113.252.45:4646`.
- Tailscale ping to primary server `100.75.75.39` succeeded; Nomad server still reports `No cluster leader`.
- Secondary configured server `100.87.219.108:4647` times out and Tailscale ping to `100.87.219.108` timed out.
- Checked disk cleanup targets: repo logs are small, `/tmp` is empty, and Docker CLI is not installed here.

## Result

- Local Nomad agent is running and responding after restart.
- Remaining issue appears cluster-side: no Nomad leader / secondary server unreachable.
Restarted the local Nomad client via launchd:

`launchctl kickstart -k gui/501/monad.nomad-client`

Current state:
- Nomad agent is running as PID `79153`.
- Local health check passes: `{"client":{"message":"ok","ok":true}}`.
- Config already had the correct Tailscale IP: `100.113.252.45`.
- Primary server `100.75.75.39` is reachable by Tailscale, but Nomad still reports `No cluster leader`.
- Secondary server `100.87.219.108` times out on Tailscale/RPC.
- No git conflicts found; no commit needed.

Updated the doctor log here: [doctor-Eliotts-Mac-mini.local-2026-06-19_1102.md](/Users/e/nomad/data/alloc/230a4756-d01e-429c-dcb6-fb7ff425c393/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-19_1102.md).