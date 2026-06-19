# claudebox: restore quorum on return

Filed by: bigo-server sweep 2026-06-19T02:06:52Z.

Current control-plane state from bigo-server:
- `V1410-1` is reachable on `100.75.75.39:4646`, but `GET /v1/agent/self` shows `raft.state=Candidate`, `leader_addr=""`, `num_peers=1`, and `latest_configuration=[V1410-1, claudebox]`.
- `GET /v1/agent/members` shows `V1410-1` `alive` and `claudebox` `failed`, so quorum is lost.
- Direct tailnet TCP probes from bigo-server still time out to `claudebox` on `22/4646/4647/4648`.
- `oraclebox1` also times out from here, so `claudebox` is the preferred path back to a second live voter.

When claudebox is reachable again, take the least-disruptive recovery path:
1. Verify Tailscale is up and `tailscale ip -4` returns `100.87.219.108`.
2. Run `~/monad/scripts/claudebox-server.sh keepalive` and use `start` if the server is not up.
3. If claudebox is not a Nomad member, rejoin with `~/monad/meta/bootstrap/join.sh 100.75.75.39 pro`.
4. If stale standalone Raft state blocks rejoin, follow `cluster/desired-servers.md` before retrying.
5. Verify recovery with `nomad server members`: `claudebox` should be `alive` and a leader should exist again.
6. Run `~/monad/meta/agent/ensure-engines.sh` after rejoin so engine metadata is advertised.

Avoid destructive actions: no data wipes, no force-pushes, and no cluster-wide restarts.
