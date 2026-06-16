# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_1629
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTARTED; CLUSTER NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 2.04%/day — will hit 95% in ~2.0 days

## Warnings

- Git has       19 uncommitted changes
- Disk usage is 91%

## Actions Taken

- Checked macOS LaunchAgent `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Verified active config `/Users/e/nomad/config/client.hcl` uses current Tailscale IP `100.113.252.45`.
- Restarted Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified new Nomad agent PID `26647` listening on `100.113.252.45:4646`; local agent API responds.
- Confirmed server `100.75.75.39:4646` is reachable, but Nomad server status reports `No cluster leader`; `claudebox.global` is failed, leaving `V1410-1.global` alive but not leader.

## Result

- Local Nomad agent is running/responding after restart.
- Remaining blocker is cluster-side leader/quorum recovery, not local agent startup.
Done. I checked the macOS Nomad client config, restarted the `monad.nomad-client` LaunchAgent, and verified the local Nomad agent is now running as PID `26647` and responding on `100.113.252.45:4646`.

The remaining blocker is cluster-side: `100.75.75.39:4646` is reachable, but Nomad reports `No cluster leader`; `V1410-1.global` is alive and `claudebox.global` is failed.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-16_1629.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_1629.md)