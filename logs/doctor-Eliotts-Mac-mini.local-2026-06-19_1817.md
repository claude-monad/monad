# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-19_1817
**Node:** Eliotts-Mac-mini.local

**Status: PARTIAL - LOCAL FIXES APPLIED**

## Issues

- Nomad local agent was already running as PID 23419 with `/Users/e/nomad/config/client.hcl`; config advertises current Tailscale IP `100.113.252.45`.
- Local Nomad API responded, and `100.75.75.39:4646` was reachable, but the server returned `No cluster leader`; `nomad server members` showed only `V1410-1` alive and not leader.
- Git dirty state was stashed, repo fast-forwarded to `origin/main`, local changes reapplied, conflicts resolved keeping both versions, and collided local tasks were preserved as `t-0159`/`t-0160`.

## Warnings

- Disk usage is 91%; `logs/` is ~1.2M and `/tmp` is empty, Docker is unavailable, so no useful safe cleanup was available.
