# Node Doctor Report: bigo-server

**Time:** 2026-07-19_1204
**Node:** bigo-server

**Status: NEEDS ATTENTION**

## Result

- Nomad is active; `/etc/nomad.d` validates and the local client health check passes.
- Restarted `tailscaled`; this node reconnected and is online.
- Retest of `100.75.75.39:4646` still timed out. Tailscale reports `v1410-1` offline since 2026-07-02 with an expired node key; recovery requires action on that host.
- No Git conflicts found. Disk is 80% used (22 GB free), so no cleanup or Docker prune was needed.

## Remaining issue

- Nomad server `100.75.75.39` must be powered/reconnected and run `tailscale up` to renew authentication before this client can rejoin.
Local Nomad and Tailscale are healthy after restarting `tailscaled`, but `100.75.75.39` remains offline with an expired Tailscale node key. It requires `tailscale up` on `v1410-1`.

No Git conflicts or disk-full condition were found. Updated [doctor log](/home/bigo/Documents/monad/logs/doctor-bigo-server-2026-07-19_1204.md).