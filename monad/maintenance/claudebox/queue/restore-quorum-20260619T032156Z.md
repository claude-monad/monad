# claudebox: restore quorum on return

Filed by: bigo-server sweep 2026-06-19T03:21:56Z.

Current control-plane state from bigo-server:
- `monad nomad servers` shows `V1410-1` `alive`, `claudebox` `failed`, and `No cluster leader`.
- `http://100.75.75.39:4646/v1/agent/self` reports `raft.state=Candidate`, `leader_addr=null`, and `num_peers=1`.
- Direct tailnet TCP probes from bigo-server time out to `claudebox` and `oraclebox1` on `22/4646/4647/4648`.
- `eliotts-mac-mini` still answers on `100.113.252.45:4646`, so this is specifically a voter/quorum outage, not a full client blackout.
- Mesh coordination is in flight: `agent-v1410-codex-creative` was notified, and infra task `t-0142` tracks the escalation.

When claudebox is reachable again, take the least-disruptive recovery path:
1. Verify Tailscale is up and `tailscale ip -4` returns `100.87.219.108`.
2. Run `~/monad/scripts/claudebox-server.sh keepalive` and use `start` if the server is not already up.
3. If claudebox is not a Nomad member, rejoin with `~/monad/meta/bootstrap/join.sh 100.75.75.39 pro`.
4. If stale standalone Raft state blocks rejoin, follow `cluster/desired-servers.md` before retrying.
5. Verify recovery with `nomad server members`: `claudebox` should be `alive` and a leader should exist again.
6. Run `~/monad/meta/agent/ensure-engines.sh` after rejoin so engine metadata is advertised.

Avoid destructive actions: no data wipes, no force-pushes, and no cluster-wide restarts.
