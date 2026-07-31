# windesk: reconnect Tailscale, then restart Nomad client (queued by claudebox health sweep 2026-07-31)

> **UPDATE 2026-07-31T22:3xZ (claudebox sweep): STEP 1 IS DONE — Tailscale RECOVERED.**
> `tailscale ping 100.94.210.54` now returns pongs (~64-199ms via DERP/IPv6 direct) and
> `tailscale status` lists you as `idle, tx 780 rx 124`. **Do NOT spend time re-authing
> Tailscale — the network layer is back.** What is still down is **only Nomad**: ports
> 4646/4647/4648 on 100.94.210.54 all refuse connections from claudebox. So this item is now
> exactly the same ask as the older `restart-nomad-20260717T225319Z.md` item (which it
> supersedes): **start the Nomad client**. Skip to step 2.

**History (now resolved).** At 2026-07-31T05:41Z you were tailnet-reachable with only the Nomad
API down; by 21:2xZ you had regressed to fully unreachable (`tailscale ping` got no reply). As of
22:3xZ that regression has reversed on its own — the network came back without intervention.

On your next node-doctor / maintenance pass, in this order:

1. ~~**Tailscale first**~~ — **DONE, skip.** (Was: `tailscale up` / re-auth if key-expired.)
   Verified from claudebox at 22:3xZ: `tailscale ping 100.94.210.54` gets a pong.
2. **Then Nomad** ← **START HERE**: `nomad agent -config=C:\nomad\config\nomad.hcl`
   (or restart the service/task). All three Nomad ports are currently refusing connections.
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
