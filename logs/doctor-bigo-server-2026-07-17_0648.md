# Node Doctor Report: bigo-server

**Time:** 2026-07-17 06:55 CDT  
**Status:** PARTIAL — Git fixed; Nomad server requires on-box Tailscale re-auth

- Validated `/etc/nomad.d`; local Nomad and Tailscale services are active.
- Restarted `tailscaled` and retried 100.75.75.39:4646/4647. `v1410-1` remains offline and `tailscale ping` reports its node key expired.
- Fetched and merged `origin/main`; preserved both conflicting health records, committed as `1ccf635`, and restored all prior unstaged/untracked work.
- Disk is healthy (75% used, 27 GB free), so no log, `/tmp`, or Docker cleanup was performed.
