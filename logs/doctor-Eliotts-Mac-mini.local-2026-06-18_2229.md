# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-18_2229
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Predictions

- ⚠ Disk usage trending up at 0.87%/day — will hit 95% in ~2.3 days

## Warnings

- Git has        2 uncommitted changes
- Disk usage is 93%

## Actions Taken

- Checked macOS launchd service `monad.nomad-client`; Nomad was running from `/Users/e/nomad/config/client.hcl`.
- Verified advertised Tailscale IP matches config: `100.113.252.45`.
- Restarted Nomad with `launchctl kickstart -k gui/$(id -u)/monad.nomad-client`.
- Verified local Nomad health endpoint after restart: client `ok`, new PID `88195`.
- Checked server reachability: Tailscale reaches `100.75.75.39`, but Nomad returns `No cluster leader`; secondary server `100.87.219.108` is timing out.

## Result

- Local Nomad agent is running/responding.
- Node registration is still blocked by upstream Nomad server quorum/leadership, not the local client.
Handled the local Nomad issue.

Nomad was already present but I restarted the macOS launchd job `monad.nomad-client`. It is now running as PID `88195`, and `http://127.0.0.1:4646/v1/agent/health` returns client `ok`.

The remaining failure is upstream: the client cannot register because Nomad server `100.75.75.39` reports `No cluster leader`, and secondary server `100.87.219.108` times out. Tailscale can reach `100.75.75.39`.

Updated the doctor report here: [doctor log](/Users/e/nomad/data/alloc/230a4756-d01e-429c-dcb6-fb7ff425c393/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-18_2229.md).