# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-19_0522
**Node:** Eliotts-Mac-mini.local
**Status:** local Nomad agent restarted; server still needs attention

## Actions

- Checked LaunchAgent: `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked config: `/Users/e/nomad/config/client.hcl`.
- Verified Tailscale is up; node IP is `100.113.252.45` and matches Nomad advertise config.
- Restarted Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Confirmed new Nomad process: `/Users/e/nomad/bin/nomad agent -config=/Users/e/nomad/config/client.hcl`.
- Confirmed local health: `/v1/agent/health` returns `client ok`.

## Remaining

- Cluster calls still fail because Nomad server `100.75.75.39` reports/times out with no cluster leader.
- Client log shows repeated `rpc error: No cluster leader` while registering.
- Disk is at 90% on `/System/Volumes/Data`; Nomad log warns GC is skipped above the 90% threshold.
Handled. Nomad client was restarted via `launchctl kickstart -k gui/501/monad.nomad-client`.

Verified:
- LaunchAgent is running with PID `28255`
- Local Nomad health returns `{"client":{"message":"ok","ok":true}}`
- Tailscale IP `100.113.252.45` matches Nomad advertise config

Remaining issue is upstream: cluster calls still fail because Nomad server `100.75.75.39` reports/times out with `No cluster leader`.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-19_0522.md](/Users/e/nomad/data/alloc/230a4756-d01e-429c-dcb6-fb7ff425c393/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-19_0522.md).