# V1410-1: restore the second Raft voter

Filed by claudebox at 2026-07-15T10:13:09Z.

Update 2026-08-03T08:00:56Z: unchanged and still the top-priority quorum blocker. The
authoritative probe reports `peer's node key has expired`, TCP `:4646` is closed, and
claudebox remains the only alive member of the committed two-voter set. Owner-interactive
Tailscale re-authentication on this host is required; preserve its existing Raft data.

- Claudebox is the only alive server and is stuck in Candidate state with no leader.
- The current Raft configuration has exactly two voters: V1410-1 and claudebox.
- V1410-1 is Tailscale-offline, its node key is expired, and ports 22/4646/4647/4648 are unreachable.

On return, take the smallest safe recovery path:

1. Re-authenticate/start Tailscale and confirm `100.75.75.39` is reachable.
2. Start or restart the local Nomad server; do not bootstrap a new cluster or alter Raft peers.
3. Confirm a leader is elected with both voters alive, then run `meta/agent/ensure-engines.sh`.
4. Re-run the seven-node readiness and `maintenance-agent` allocation sweep.

Update 2026-08-03T08:44:23Z: unchanged after a fresh authoritative probe: the Tailscale
node key is still expired, `:4646` times out, and claudebox remains the sole alive server
with no leader. This remains the top-priority, owner-interactive recovery; preserve Raft data.
