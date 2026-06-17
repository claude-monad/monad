# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-16_2306
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has       30 uncommitted changes

## Actions

- Checked `/Users/e/nomad/config/client.hcl`: bind/advertise address matches Tailscale IP `100.113.252.45`.
- Restarted launchd service `monad.nomad-client` with `launchctl kickstart -k`; PID changed `37506` -> `62130`.
- Verified local Nomad client API is healthy at `http://100.113.252.45:4646/v1/agent/health`.

## Result

- Local Nomad agent is running/responding.
- Cluster still has no Nomad leader: `V1410-1` alive but not leader; `claudebox` server is failed/offline.
Handled the Nomad agent issue.

Restarted `monad.nomad-client` via launchd; PID changed `37506` -> `62130`. Verified the local Nomad API is responding:

```text
{"client":{"message":"ok","ok":true}}
```

Updated the doctor log at [doctor-Eliotts-Mac-mini.local-2026-06-16_2306.md](/Users/e/nomad/data/alloc/09ee9bdc-4ac8-093f-9262-e5459b00b68b/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-16_2306.md).

Remaining cluster issue: Nomad still has no leader because `V1410-1` is alive but not leader and `claudebox` is failed/offline.