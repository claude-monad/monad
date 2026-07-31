# windesk: reconnect Tailscale, then restart Nomad client (queued by claudebox health sweep 2026-07-31)

**Regression since the 2026-07-17 queue item.** Earlier today (2026-07-31T05:41Z) you were still
*tailnet-reachable* with only the Nomad API down. As of 2026-07-31T21:2xZ you are **fully
unreachable**: `tailscale ping 100.94.210.54` returns "no reply", and `tailscale status` from
claudebox shows no active session for you. So the earlier "restart Nomad" item cannot even be
attempted remotely — the network layer has to come back first.

On your next node-doctor / maintenance pass, in this order:

1. **Tailscale first**: `tailscale status`; if logged out or key-expired, `tailscale up`
   (re-auth interactively if the node key expired — same failure mode as v1410-1, see GH #8).
   Confirm from claudebox: `tailscale ping 100.94.210.54` gets a pong.
2. **Then Nomad**: `nomad agent -config=C:\nomad\config\nomad.hcl` (or restart the service/task).
3. **Point at the live server** — `100.87.219.108:4647` (claudebox). Do **not** use
   `100.75.75.39:4647` (v1410-1) as the sole server: its Tailscale node key is expired.
   Ideally list **both** so the config survives either server returning.
4. **Re-advertise engines**: `powershell meta/agent/ensure-engines.ps1`
   (point it at `http://100.87.219.108:4646`, not the default dead `NOMAD_ADDR`).
5. **Verify locally**: `curl http://100.94.210.54:4646/v1/agent/health` shows client ok.

Note: the cluster still has **no Raft leader** — the committed voter set is exactly
{v1410-1, claudebox} (per t-0340; oraclebox1 is *not* a voter), and v1410-1 is key-expired, so
1/2 voters are alive. Your client will sit leaderless and cannot register until quorum returns.
That is expected — the goal here is a healthy, reachable local agent ready for leader return.

Release claim when done: `bash scripts/cluster-memory.sh set "health:windesk" "DONE-<utc-timestamp>"`
