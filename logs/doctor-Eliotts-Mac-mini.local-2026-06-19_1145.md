# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-19_1145
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL NOMAD RESTARTED**

## Issues

- Nomad agent is not running or not responding

## Warnings

- Git has        9 uncommitted changes
- Disk usage is 91%

## Actions

- 2026-06-19 11:48 MDT: checked macOS launchd config at `/Users/e/Library/LaunchAgents/monad.nomad-client.plist`; it runs `/Users/e/nomad/start.sh`.
- Restarted local Nomad client with `launchctl kickstart -k gui/$(id -u)/monad.nomad-client`.
- Verified local Nomad is running as PID 83989 with config `/Users/e/nomad/config/client.hcl`; local API `127.0.0.1:4646/v1/agent/self` responds.
- Verified `100.75.75.39:4646` and `100.75.75.39:4647` are reachable.
- Remaining issue: Nomad server reports `No cluster leader`; `nomad server members` shows only `V1410-1.global` alive and not leader. Local restart cannot fix this safely.
- Disk pressure checked: data volume 91%, repo logs 1.2M, `/Users/e/nomad/logs` 37M, `/tmp` empty, `docker` not installed; no useful safe cleanup target found.
- Git status checked: uncommitted changes present, but no merge conflicts reported.
Local Nomad agent was already present but stale, so I restarted the macOS launchd job `monad.nomad-client` via `launchctl kickstart -k gui/$(id -u)/monad.nomad-client`.

Verified:
- Local Nomad is running as PID `83989`.
- Local API responds at `127.0.0.1:4646`.
- Config in use: `/Users/e/nomad/config/client.hcl`.
- Server `100.75.75.39` is reachable on `4646` and `4647`.

Remaining issue is upstream: the Nomad server reports `No cluster leader`; `nomad server members` shows only `V1410-1.global` alive and not leader. I did not force any cluster recovery.

Updated the doctor log here: [doctor-Eliotts-Mac-mini.local-2026-06-19_1145.md](/Users/e/nomad/data/alloc/230a4756-d01e-429c-dcb6-fb7ff425c393/maintainer/local/monad/logs/doctor-Eliotts-Mac-mini.local-2026-06-19_1145.md).