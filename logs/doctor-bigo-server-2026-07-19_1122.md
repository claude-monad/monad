# Node Doctor Report: bigo-server

**Time:** 2026-07-19_1122
**Node:** bigo-server

**Status: PARTIAL — Git repaired; remote server needs on-box recovery**

## Actions

- Restarted local `tailscaled`, ran `tailscale up`, and verified this node reconnected as `100.78.218.70`.
- Confirmed `v1410-1` (`100.75.75.39`) is unreachable because its Tailscale node key expired; Nomad ports 4646/4647 time out. Local Nomad is active with the correct config. Remote Tailscale re-authentication and Nomad verification require on-box/provider access.
- Fast-forwarded 20 upstream commits and retained both nodes' changes. Preserved both event streams, kept the newest cluster-memory records, and renumbered colliding local tasks `t-0274`–`t-0277` to `t-0293`–`t-0296`.
