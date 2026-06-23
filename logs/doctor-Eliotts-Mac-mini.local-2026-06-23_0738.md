# Node Doctor Report: Eliotts-Mac-mini.local

**Time:** 2026-06-23_0738
**Node:** Eliotts-Mac-mini.local

**Status: NEEDS ATTENTION**

## Issues

- Cannot reach Nomad server at 100.75.75.39:4646
- Git cannot fast-forward — may have conflicts or diverged history

## Warnings

- Repo permissions had drifted — repaired
- Git has        5 uncommitted changes

## Actions

- Checked Nomad launchd job `monad.nomad-client`; it is running from `/Users/e/nomad/start.sh` with config `/Users/e/nomad/config/client.hcl`.
- Checked server reachability: `nc` to `100.75.75.39:4646`, `nomad server members`, and `tailscale ping 100.75.75.39` all timed out.
- Ran `tailscale up`; local Tailscale netcheck is healthy and `bigo-server` is reachable, but `v1410-1` / `100.75.75.39` is still reported offline.
- Preserved local Git changes with stash, fast-forwarded `main` from `e8afc35` to `97e92e4`, and reapplied the stash with no conflicts.
- Disk check: data volume is 89% used; repo logs are 1.6M, `/tmp` is empty, and Docker is not installed/on PATH, so no cleanup was useful.

## Result

- Git fast-forward issue handled; local generated state will be committed with this report.
- Nomad server remains unreachable from this node; likely remote `v1410-1`/Tailscale-side issue.
