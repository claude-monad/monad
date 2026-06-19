# Node Doctor Report: bigo-server

**Time:** 2026-06-19_0551
**Node:** bigo-server

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding
- Git fetch failed — network issue or auth problem

## Warnings

- Tailscale command not found
- Nomad server reachable but no leader advertised
- Repo permissions had drifted — repaired
- Git has 84 uncommitted changes
- Disk usage is 93%

## Actions

- Confirmed local Nomad client is healthy at `http://100.78.218.70:4646`; `/etc/nomad.d/nomad.hcl` exists on this node. Skipped restart because the agent is live.
- Patched `scripts/node-doctor.sh` to probe common local Nomad bind addresses before flagging `Nomad agent is not running or not responding`, which avoids the false negative seen here.
- Retried `git fetch origin`; it succeeded (`origin/main` updated locally). No auth change or conflict resolution was needed.
- Verified Tailscale is up via `tailscale0` and the Nomad server at `100.75.75.39:4646` is reachable, but it still has no cluster leader.

## Remaining

- Cluster control plane is still degraded upstream: `100.75.75.39` answers `/v1/agent/self`, but leader discovery still times out.
