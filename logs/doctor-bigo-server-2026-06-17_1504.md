# Node Doctor Report: bigo-server

**Time:** 2026-06-17_1504
**Node:** bigo-server

**Status: NEEDS ATTENTION**

## Issues

- Git cannot fast-forward — may have conflicts or diverged history

## Actions

- Fetched `origin` and merged `origin/main` into `main` as commit `2ff5f9b`, clearing the branch divergence.
- Restored the pre-merge local worktree after the merge and kept both health-record versions in `cluster-memory.json` by preserving the timestamped remote entries alongside the newer local status.
- Repo history is no longer behind `origin/main`; local uncommitted node-doctor/worktree changes were preserved.

## Predictions

- ⚠ Disk usage trending up at 1.15%/day — will hit 95% in ~1.7 days

## Warnings

- Tailscale command not found
- Nomad server reachable but no leader advertised
- Repo permissions had drifted — repaired
- Git has 16 uncommitted changes
- Disk usage is 93%
