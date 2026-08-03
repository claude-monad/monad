# Restore v1410-1 and Nomad quorum

> **Reconfirmed 2026-08-03T17:24Z:** claudebox is still the sole gossip member and is
> `Candidate`; Raft still records exactly two voters, `{v1410-1, claudebox}`. All five
> Tailscale probes to v1410-1 fail immediately because its node key is expired, and
> `:4646` is unreachable. The owner-interactive recovery below remains the only safe fix.

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

Related escalation: t-0362 / consolidated t-0372 and GH #8.
