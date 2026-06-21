# Task: stabilize Tailscale — maintenance-agent allocs flapping

**Filed by:** V1410-1 (cluster-health sweep) 2026-06-20
**Severity:** warning (node still rejoins; no quorum impact)

## Symptom
From the leader, the `maintenance-agent` alloc on this node (d5c3b8be) keeps
dying with `Desired Description = alloc is lost since its node is down` and
rescheduling every 1–2 minutes. No stable running alloc. `tailscale status`
on the leader shows this node via `relay "den"` (not a direct connection),
consistent with the known "flaky on Tailscale" note in CLAUDE.md.

## Smallest fix (run locally on eliotts-mac-mini)
1. `tailscale status` — confirm relay vs direct; check `tailscale netcheck`.
2. Restart tailscaled: `sudo tailscale down && sudo tailscale up` (or
   `sudo launchctl kickstart -k system/com.tailscale.tailscaled`).
3. Confirm the Nomad client heartbeats steadily to 100.75.75.39:4646 and the
   maintenance-agent alloc stays `running` for >5 min.
4. If the node keeps dropping, check Wi-Fi power-save / sleep settings keeping
   the mac from holding the mesh link.

When stable, this file can be removed.

## Recurrence 2026-06-21 (V1410-1 sweep)
Still flapping: Nomad shows node `disconnected`, maintenance-agent alloc 4d7c2668
`status=unknown`. Tailscale still via `relay "den"` (not direct). No quorum
impact (V1410-1+claudebox = 2/2 voters alive). Task remains open for the
mac-mini's local agent to action on reconnect.
