# Node Doctor Report: bigo-server

**Time:** 2026-06-19_0745
**Node:** bigo-server

**Status: RESOLVED**

## Issues

- Git fetch had failed earlier

## Warnings

- Tailscale command not found
- Nomad server reachable but no leader advertised
- Repo permissions had drifted — repaired
- Git has 86 uncommitted changes
- Disk usage is 93%

## Actions Taken

- Verified `origin` HTTPS remote is reachable and responding from this node
- Confirmed auth is not the blocker for fetch on this repo
- Ran `git fetch origin` successfully; updated `origin/main` from `196b1d4` to `b2c1a40`
- Did not run pull/merge because the worktree is dirty and `main` is both ahead and behind
