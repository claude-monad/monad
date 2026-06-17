# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_0115
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTARTED**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       35 uncommitted changes

## Actions

- Checked macOS launchd config: `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Checked Nomad config: `/Users/e/nomad/config/client.hcl`; Tailscale bind IP matches `tailscale ip -4` (`100.113.252.45`).
- Restarted local Nomad client with `launchctl kickstart -k gui/$(id -u)/monad.nomad-client`; new PID `61598`.
- Verified local agent endpoint: `http://100.113.252.45:4646/v1/agent/self` responds.
- Server `100.75.75.39` reachable on `4646/4647`, but Nomad still returns `No cluster leader`; likely cluster/quorum issue, not local process/config.
- Disk checked: data volume at 90%; target cleanup dirs are small (`logs` 1.1M, `/Users/e/nomad/logs` 30M, `/tmp` 0B); Docker daemon not running, so no prune performed.
- Git checked: uncommitted files present, no merge-conflict paths.
Local Nomad client was restarted via launchd and is now responding on `http://100.113.252.45:4646/v1/agent/self`. The remaining failure is upstream: `100.75.75.39` is reachable on Nomad ports, but the cluster still returns `No cluster leader`.

Updated the doctor log here: [doctor-Eliotts-Mac-mini.local-2026-06-17_0115.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_0115.md). No Git conflicts were present; disk cleanup targets were tiny and Docker daemon was not running, so no prune was performed.