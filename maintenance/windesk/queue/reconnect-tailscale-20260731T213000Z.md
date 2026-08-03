# windesk: reconnect Tailscale, then restart Nomad client (queued by claudebox health sweep 2026-07-31)

> **UPDATE 2026-08-03T07:17Z:** authoritative `tailscale ping -c 5` succeeds (direct IPv6,
> 275 ms), while TCP :4646 is closed and the Codex gateway on :8300 is unreachable. Tailscale
> is healthy; start at step 2 and restore the local Nomad client/maintenance loop on-box.

> **UPDATE 2026-08-03T05:55Z:** windesk has flapped offline again. It was reachable at
> 05:15Z, but then failed **two independent `tailscale ping -c 5` passes (10/10 timeouts)**;
> Tailscale reports it offline with last-seen 05:50Z and TCP :4646 is closed. Wake/power on
> the host and run step 1 again, then continue with the existing Nomad recovery steps. This
> does not look like an expired key: the host has repeatedly returned without re-auth, so
> check Windows sleep/hibernate and service-at-boot settings.

> **UPDATE 2026-08-01T11:0xZ (claudebox sweep): ✅ TAILSCALE IS FINE — START AT STEP 2 (Nomad).**
> This supersedes *both* notes below. windesk answers `tailscale ping -c 5 100.94.210.54`:
> probe 1 timed out, probe 2 got a pong via DERP(den) in 964ms, then a **direct** IPv6 path
> (`[2607:fb90:...]:41641`) in 474ms. Do not re-auth Tailscale.
>
> **The 10:33Z "8/8 pings failed" reading was a probe artifact, not a regression.** Those were
> single-shot `tailscale ping` calls; a DERP-only peer has no warm path until the relay
> handshake finishes, so the first probes time out before it completes. eliotts-mac-mini
> produced the identical false negative in the same sweep (`-c 1` no-reply, `-c 5` pong on
> probe 5). **Always probe with `-c 5` and only call a peer down if all 5 fail** — see the
> expanded note in `meta/CLUSTER-HEALTH.md`. Genuinely-down peers (death-star, oraclebox1,
> v1410-1) stayed silent across all 6 probes.
>
> So the "three flaps in four days" story is mostly measurement noise. The fact that has held
> on **every** observation since 07-31T05:41Z is the one below: **Nomad on windesk is down**
> (:4646 refuses connections). That is the actual work item.

**History.** 07-31T05:41Z tailnet-reachable, Nomad API down → 21:2xZ fully unreachable → 22:3xZ
recovered on its own → **08-01T~05:30Z unreachable again (current state).** This peer has now
flapped three times in four days, which is itself the finding: the underlying cause is likely the
machine sleeping/powering off rather than a Tailscale auth problem (`rx 0` on every observation
means claudebox has never received bytes back). Worth checking Windows sleep/hibernate settings
and whether tailscaled is set to run as a service at boot.

On your next node-doctor / maintenance pass, in this order:

1. **Tailscale/reachability first — ACTIVE AGAIN as of 2026-08-03T05:55Z.** Wake/power on
   the host and verify `tailscale ping -c 5`; all ten probes across two passes failed in this
   sweep. Re-authenticate only if the on-box client explicitly reports an auth/key problem.
2. **Then Nomad** ← **START HERE.** `nomad agent -config=C:\nomad\config\nomad.hcl`
   (or restart the service/task). :4646 was refusing connections on 07-31T22:3xZ and still
   refuses as of 08-01T11:0xZ, while the host itself pings fine — so this is a dead local
   agent, not a network problem. Also check whether tailscaled/Nomad are set to start as
   services at boot, since the host does appear to sleep.
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
