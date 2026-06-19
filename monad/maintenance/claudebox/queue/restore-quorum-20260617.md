# claudebox: restore quorum on return

Filed by: bigo-server sweep 2026-06-17.

Current control-plane state from bigo-server:
- `V1410-1` answers on `100.75.75.39:4646` but `/v1/agent/self` shows `raft.state=Candidate`, `num_peers=1`, and `latest_configuration=[V1410-1, claudebox]`.
- `monad nomad servers` shows `V1410-1` `alive`, `claudebox` `failed`, and `No cluster leader`.
- Direct tailnet TCP probes from bigo-server show `claudebox` timing out on `22/4646/4647/4648`.
- `oraclebox1` is also unreachable, so restoring `claudebox` is the smallest path back to quorum.

When claudebox is reachable again, take the least-disruptive recovery path:
1. Verify Tailscale is up and `tailscale ip -4` returns `100.87.219.108`.
2. Run `~/monad/scripts/claudebox-server.sh keepalive` (or `start` if needed).
3. If claudebox is not a Nomad member, rejoin with `~/monad/meta/bootstrap/join.sh 100.75.75.39 pro`.
4. If stale standalone Raft state blocks rejoin, follow `cluster/desired-servers.md` before retrying.
5. Verify recovery with `nomad server members`: `claudebox` should be `alive` and a leader should exist again.
6. Run `~/monad/meta/agent/ensure-engines.sh` after rejoin so engine metadata is advertised.

Avoid destructive actions: no data wipes, no force-pushes, and no cluster-wide restarts.
