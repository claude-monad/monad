# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-17_0435
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - local agent restored, cluster still unhealthy**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       38 uncommitted changes

## Actions

- Checked `/Users/e/nomad/config/client.hcl`: `nomad config validate` passed; Tailscale IP is `100.113.252.45` and matches config.
- Found launchd job `monad.nomad-client`; restarted with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified new Nomad client PID `8045` listening on `100.113.252.45:4646`; `/v1/agent/self` responds.
- Primary server `100.75.75.39:4647` is reachable, but Nomad status/leader checks still time out or report no leader. Configured peer `100.87.219.108:4647` times out.
- Disk is at 90%; repo logs are only 1.2M, `/tmp` is empty, and `docker` CLI is not installed, so no cleanup was useful.
- No git merge conflicts found; no conflict commit needed.
Done. Restarted the local Nomad client via launchd; it is now running as PID `8045` and its API responds on `100.113.252.45:4646`.

Updated the doctor log: [doctor-Eliotts-Mac-mini.local-2026-06-17_0435.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-17_0435.md:1).

Remaining issue: the local agent is healthy, but the Nomad cluster is still unhealthy upstream. `100.75.75.39:4647` is reachable, but leader/status checks time out or report no leader; configured peer `100.87.219.108:4647` times out. No git conflicts were present, so no conflict commit was needed.