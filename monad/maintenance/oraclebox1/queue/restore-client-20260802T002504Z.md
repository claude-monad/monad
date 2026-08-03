# oraclebox1: restore tailnet and Nomad client on return

Filed by claudebox at 2026-08-02T00:25:04Z.

Update 2026-08-03T08:00:56Z: all five Tailscale probes still timed out and TCP `:4646`
remains closed. No in-band recovery path is available; restore this host on-box, preserving
Nomad data, but note that it is not currently a committed voter and cannot by itself elect a
leader.

Current state:

- All five authoritative Tailscale probes to `100.125.210.126` timed out and TCP `:4646` is closed.
- The current committed Raft voter set is exactly `{v1410-1, claudebox}`; oraclebox1 is **not**
  currently a voter, so restoring oraclebox1 alone cannot recover quorum.
- Older queue entries that describe oraclebox1 as a third voter are stale; do not bootstrap a
  replacement cluster or perform Raft peer surgery.

On return, take the smallest safe recovery path:

1. Verify the host is powered on and Tailscale is up.
2. Start/restart the existing Nomad agent without deleting its data directory.
3. Configure its client server list to include the live server `100.87.219.108:4647` first.
4. Run `meta/agent/ensure-engines.sh` and confirm the local client health endpoint is healthy.
5. After v1410-1 restores quorum, verify oraclebox1 is `ready`, `eligible`, and has a live
   maintenance loop/allocation. Do not promote it to voter without a healthy leader and an
   explicit cluster-level plan.
