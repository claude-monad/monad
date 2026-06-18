# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_1857
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 2.61%/day — will hit 95% in ~1.1 days

## Warnings

- Git has       56 uncommitted changes
- Disk usage is 92%

## Doctor Actions

- Checked macOS Nomad LaunchAgent: `monad.nomad-client` is running as PID 74057 from `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked config: `/Users/e/nomad/config/client.hcl` advertises current Tailscale IP `100.113.252.45`; Tailscale is up.
- Verified local agent health: `http://127.0.0.1:4646/v1/agent/health?type=client` returned ok.
- Verified Nomad server `100.75.75.39` is reachable on Nomad ports; did not reconnect Tailscale.
- Found remaining Nomad error is upstream: server side reports `No cluster leader`; peer `claudebox` is failed/offline.
- Checked git conflicts: none found; left existing uncommitted changes untouched.
- Disk cleanup check: no old repo logs to delete, `/tmp` is empty, Docker is not installed.

**Result:** Local Nomad agent is running/responding. Cluster still needs attention for leadership/quorum.
Updated [doctor log](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_1857.md).

Local Nomad is running and responding via `monad.nomad-client` PID `74057`; config advertises the current Tailscale IP. I did not restart it because the local agent health endpoint is ok. The remaining failure is upstream: Nomad reports `No cluster leader`, with `claudebox` failed/offline.

Also checked: server `100.75.75.39` reachable, no git conflicts, no old repo logs to delete, `/tmp` empty, Docker unavailable.