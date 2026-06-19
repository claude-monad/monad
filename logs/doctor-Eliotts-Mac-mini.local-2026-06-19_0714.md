# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-19_0714
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has        7 uncommitted changes

## Actions

- Checked `/Users/e/nomad/config/client.hcl`; advertise IP matches local Tailscale IP `100.113.252.45`.
- Found Nomad running under LaunchAgent `monad.nomad-client`; restarted it with `launchctl kickstart -k gui/$(id -u)/monad.nomad-client`.
- Nomad restarted successfully as PID `60149`; local health endpoint returns OK.
- Confirmed `100.75.75.39:4646` and `:4647` are reachable over Tailscale.
- Remaining blocker: Nomad server responses/logs report `No cluster leader`; second configured server `100.87.219.108:4647` times out.
- No git conflicts found. Disk cleanup not needed for repo logs (`1.2M`), `/tmp` empty, Docker CLI absent.
Restarted the local Nomad LaunchAgent `monad.nomad-client`. Nomad is now running as PID `60149`, and `http://127.0.0.1:4646/v1/agent/health` returns OK.

Remaining blocker is cluster-side: the reachable server `100.75.75.39` reports/times out with `No cluster leader`, and the second configured server `100.87.219.108:4647` times out. No git conflicts were present.

Updated [doctor log](/Users/e/nomad/data/alloc/230a4756-d01e-429c-dcb6-fb7ff425c393/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-19_0714.md).