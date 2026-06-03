# Node Doctor Report: bigo-server

**Time:** 2026-06-03_1204
**Node:** bigo-server

**Status: RESOLVED**

## Issues

- ~~Git cannot fast-forward — may have conflicts or diverged history~~ **FIXED**
  - Root cause: working tree had uncommitted appends to `logs/events.jsonl` and
    `logs/metrics-bigo-server.csv` while branch was 6 commits behind origin/main,
    blocking the fast-forward.
  - Fix: committed local log/metric updates, then `git rebase origin/main`
    (applied cleanly, no conflicts). Re-fetched + rebased once more after a
    concurrent push from another node, then pushed. Now in sync (pushed a4e2132).

## Warnings

- ~~Git has 1 uncommitted changes~~ committed and pushed.
- Disk usage is 87% (90G/109G used, **14G free**) — monitored, not urgent.
  `logs/` dir is only 276K so not the driver; no cleanup needed this pass.
