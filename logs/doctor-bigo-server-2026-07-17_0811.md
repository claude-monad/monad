# Node Doctor Report: bigo-server

**Time:** 2026-07-17_0811
**Status:** PARTIAL — local node repaired; remote server needs on-box re-auth

- Restarted `tailscaled`, ran `tailscale up`, and verified the local backend is Running at `100.78.218.70`.
- Confirmed `v1410-1` (`100.75.75.39`) is offline and its Tailscale node key expired 2026-07-02. Nomad ports 4646/4647 still time out; re-authentication on that host/provider console is required.
- Checked `/etc/nomad.d/nomad.hcl`, restarted the local Nomad client, and verified its API at `100.78.218.70:4646`.
- Fast-forwarded to `origin/main` and reconciled overlapping cluster-memory, event-log, and task-sequence changes while retaining both versions. Renumbered the colliding local `t-0245` record to `t-0249`.
- Disk is 75% used with 27 GB free; no log/tmp/Docker cleanup was needed.
