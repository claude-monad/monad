# Node Doctor Report: bigo-server

**Time:** 2026-06-19_2031
**Node:** bigo-server

**Status: FIXED**

## Issues

- Git cannot fast-forward — fixed by committing local health state, merging `origin/main`, and resolving overlapping coordination records while preserving both versions.

## Warnings

- Nomad server reachable but no leader advertised

## Actions

- Preserved local bigo-server log/metrics/task updates.
- Merged remote updates through `origin/main`.
- Resolved conflicts in `cluster-memory.json`, `.seq`, and `t-0159.json`; kept both local and remote details.
- Cleared the git dirty/behind state with commits.
