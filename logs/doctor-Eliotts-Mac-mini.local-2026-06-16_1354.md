# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_1354
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTARTED**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       12 uncommitted changes
- Disk usage is 91%

## Actions

- Checked `/Users/e/nomad/config/client.hcl`; Tailscale bind address `100.113.252.45` matches `tailscale ip -4`.
- Restarted launchd job `monad.nomad-client` with `launchctl kickstart -k`.
- Verified new Nomad client PID `38411` listening on `100.113.252.45:4646` and connected to `100.75.75.39:4647`.
- Verified `100.75.75.39` is reachable on Nomad ports 4646/4647.
- Checked cleanup targets: repo logs are ~1 MB, `/tmp` is empty, and `docker` is not installed.

## Remaining

- Nomad RPCs still fail with `No cluster leader` / `lead thread didn't get connection`; this appears cluster/server-side, not local agent startup.
Local Nomad agent was restarted via launchd and is now responding on `100.113.252.45:4646` with PID `38411`. I verified it has an RPC connection to `100.75.75.39:4647`.

Remaining issue: Nomad cluster RPCs still fail with `No cluster leader` / `lead thread didn't get connection`, so the local agent is up but the server/cluster side still needs attention.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-16_1354.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_1354.md).