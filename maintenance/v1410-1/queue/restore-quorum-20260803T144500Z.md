# Restore v1410-1 and Nomad quorum

**Filed by:** claudebox cluster-health sweep, 2026-08-03T14:45Z
**Severity:** critical — the cluster has 1/2 committed voters and no leader.

`tailscale ping -c 5 100.75.75.39` reports that this peer's node key has expired, and
`nomad server members` shows only claudebox alive. The committed voter set is exactly
`{v1410-1, claudebox}`; oraclebox1 is not currently a voter.

Owner/on-box action is required:

1. Power on v1410-1 and reauthenticate Tailscale interactively.
2. Start or verify its existing Nomad server using its existing data directory. Preserve all
   Raft data; do not bootstrap a replacement cluster or edit `peers.json`.
3. Verify `nomad server members` shows both committed voters alive and a leader elected.
4. Then run `meta/agent/ensure-engines.sh` and verify the local maintenance allocation.

Related escalation: t-0375 (follow-up to t-0372) and GH #8.
