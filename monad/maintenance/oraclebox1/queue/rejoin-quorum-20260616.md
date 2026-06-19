# oraclebox1: restore as a Nomad voter to recover quorum

Filed by: bigo-server sweep 2026-06-16.

Current cluster state from bigo-server:
- `V1410-1` is reachable on `100.75.75.39`, but `nomad server members` shows it as the only alive server and returns `No cluster leader`.
- `V1410-1` reports Raft `state=Candidate`, `num_peers=1`, and the latest voter set contains only `V1410-1` and `claudebox`.
- Direct tailnet TCP probes from bigo-server to `100.125.210.126` timed out on 22/4646/4647/4648.
- `claudebox` is also timing out, so restoring either voter is quorum-critical.

When oraclebox1 is reachable again, take the smallest safe recovery path:
1. Verify the host is powered on and Tailscale is up.
2. Restart Nomad if needed and confirm `nomad server members` shows `oraclebox1` `alive`.
3. If Nomad does not rejoin cleanly, use the node's local rejoin/bootstrap path rather than touching cluster-wide state.
4. Run `meta/agent/ensure-engines.sh` after rejoin so engine metadata is re-advertised.
5. Verify a leader exists again before attempting any wider cleanup or job repair.

Avoid destructive actions: no data wipes, no force-pushes, and no cluster-wide restarts.
