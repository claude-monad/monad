# windesk: reconnect Tailscale, then restart Nomad client (queued by claudebox health sweep 2026-07-31)

> **UPDATE 2026-08-01T10:33Z (claudebox sweep): ⚠️ REGRESSED AGAIN — STEP 1 IS BACK IN PLAY.**
> The 07-31T22:3x "Tailscale recovered, skip step 1" note below is **STALE — do not follow it.**
> As of 10:33Z windesk is **fully tailnet-unreachable again**: 8 consecutive
> `tailscale ping 100.94.210.54` attempts all timed out ("no reply"), and `tailscale status`
> lists you `offline, last seen 5h ago, tx 504504 rx 0` (i.e. last contact ~05:30Z).
> This is **not** the documented false-flap: claudebox's own netmap is fresh (its only health
> warning is DNS-servers-unreachable, with no frozen "hasn't received a network map" string),
> and the false-flap signature is ping *succeeding* while the status column says offline —
> here ping genuinely fails. **Start at step 1 again.**

**History.** 07-31T05:41Z tailnet-reachable, Nomad API down → 21:2xZ fully unreachable → 22:3xZ
recovered on its own → **08-01T~05:30Z unreachable again (current state).** This peer has now
flapped three times in four days, which is itself the finding: the underlying cause is likely the
machine sleeping/powering off rather than a Tailscale auth problem (`rx 0` on every observation
means claudebox has never received bytes back). Worth checking Windows sleep/hibernate settings
and whether tailscaled is set to run as a service at boot.

On your next node-doctor / maintenance pass, in this order:

1. **Tailscale first** ← **START HERE (re-opened 08-01T10:33Z).** Confirm the machine is powered
   on and awake, then `tailscale status` / `tailscale up` (re-auth if the node key expired).
   Nothing below can work until `tailscale ping` from claudebox gets a pong.
2. **Then Nomad**: `nomad agent -config=C:\nomad\config\nomad.hcl`
   (or restart the service/task). All three Nomad ports were refusing connections when last
   observable (07-31T22:3xZ); they cannot be probed at all while step 1 is outstanding.
   This item supersedes the older `restart-nomad-20260717T225319Z.md`.
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
