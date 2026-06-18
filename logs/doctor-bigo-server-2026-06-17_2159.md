# Node Doctor Report: bigo-server

**Time:** 2026-06-17_2159
**Node:** bigo-server

**Status: RESOLVED**

## Issues

- Git cannot fast-forward — resolved by stashing local edits, merging `origin/main`, and restoring the local working copy.

## Actions

- Created backup branch `backup/node-doctor-bigo-server-before-merge-20260617-2159`.
- Merged upstream as `73034b8`; repo is now `ahead 20, behind 0`.
- Reapplied local changes cleanly; no conflict markers were introduced.

## Remaining Warnings

- Tailscale command not found
- Nomad server reachable but no leader advertised
- Repo permissions had drifted — repaired
- Local uncommitted changes are still present in the working copy
- Disk usage is 93%
