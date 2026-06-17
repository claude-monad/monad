# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_1352
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Actions

- Checked macOS launchd service `monad.nomad-client`; config is `/Users/e/nomad/config/client.hcl` via `/Users/e/nomad/start.sh`.
- Validated config with `nomad config validate /Users/e/nomad/config/client.hcl`: valid.
- Restarted local Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`; PID changed from 79105 to 74057.
- Verified local agent API responds on `127.0.0.1:4646`; launchd state is running.
- Verified Tailscale is up and `100.75.75.39:4646` is reachable, but Nomad returns `No cluster leader`.
- Alternate configured server `100.87.219.108:4647` times out.
- Checked for Git conflicts: none. Disk cleanup targets were not useful (`logs` 1.1M, `/tmp` 0B); Data volume remains 92%.

## Result

- Local Nomad client is running again. Remaining outage appears cluster/server-side: no Nomad leader.

## Predictions

- ⚠ Disk usage trending up at 3.39%/day — will hit 95% in ~0.9 days

## Warnings

- Git has       50 uncommitted changes
- Disk usage is 92%
Fixed the local Nomad client side and updated [the doctor log](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_1352.md).

What I did:
- Validated `/Users/e/nomad/config/client.hcl`.
- Restarted `monad.nomad-client` via launchd; PID changed `79105` -> `74057`.
- Verified local Nomad health: `client ok`.
- Verified Tailscale/server reachability to `100.75.75.39:4646`.

Remaining issue: the remote Nomad server responds, but Nomad returns `500 No cluster leader`. The local agent is running; the remaining outage is cluster/server-side.