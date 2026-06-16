# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-15_2320
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Repo permissions had drifted — repaired
- Git has        4 uncommitted changes
- Disk usage is 94%

## Fix Applied

- Checked macOS LaunchAgent: `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`.
- Validated Nomad config: `/Users/e/nomad/config/client.hcl` OK.
- Restarted local Nomad client with `launchctl kickstart -k gui/501/monad.nomad-client`.
- Verified local agent health: `http://100.113.252.45:4646/v1/agent/health` returned `ok:true`.
- Tailscale is up; server `100.75.75.39` is reachable, but Nomad HTTP on `:4646` timed out and logs still show `No cluster leader`.
- No git merge conflicts found. No old local log cleanup available; `/tmp` empty; Docker CLI not installed here.
Local Nomad was restarted via launchd and is healthy now. Verified `http://100.113.252.45:4646/v1/agent/health` returns `ok:true`; launchd shows `monad.nomad-client` running as PID `70884`.

Updated the doctor log here: [doctor-Eliotts-Mac-mini.local-2026-06-15_2320.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-15_2320.md).

Residual issue: Tailscale is up and `100.75.75.39` is reachable, but Nomad HTTP on that server times out and local logs still show `No cluster leader`, so the remaining problem appears server-side rather than this node’s agent. No git conflicts found; no cleanup was useful because `/tmp` is empty, repo logs are small, and Docker CLI is not installed here.