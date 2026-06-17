# Node Doctor Report: bigo-server

**Time:** 2026-06-17_1119
**Node:** bigo-server

**Status: NEEDS ATTENTION**

## Issues

- Git cannot fast-forward — may have conflicts or diverged history

## Predictions

- ⚠ Disk usage trending up at 1.22%/day — will hit 95% in ~1.6 days

## Warnings

- Tailscale command not found
- Nomad server reachable but no leader advertised
- Repo permissions had drifted — repaired
- Git has 15 uncommitted changes
- Disk usage is 93%

## Doctor Actions

- Merged `origin/main` into local `main` to clear the fast-forward block.
- Resolved `cluster-memory.json` conflicts by preserving both versions under distinct keys.
- Local branch is now `ahead 11` and no longer behind `origin/main`.
