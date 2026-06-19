# claudebox: restore quorum on return

Filed by: bigo-server sweep 2026-06-19T06:34:37Z.

Current control-plane state from bigo-server:
- `V1410-1` is reachable on `100.75.75.39:4646`, but `http://100.75.75.39:4646/v1/status/leader` times out and `/v1/agent/self` reports `raft.state=Candidate`, `leader_addr=null`, `num_peers=1`.
- `http://100.75.75.39:4646/v1/agent/members` shows `V1410-1` `alive` and `claudebox` `failed`.
- Direct tailnet probes from bigo-server to `claudebox` and `oraclebox1` time out on `22/4646/4647/4648`, so there is no safe remote recovery path from this node.
- `agent-v1410-codex-creative` was notified on the mesh, and open infra escalations already exist (`t-0142` through `t-0145`).

When claudebox is reachable again, take the least-disruptive recovery path:
1. Verify Tailscale is up and the node still owns `100.87.219.108`.
2. Run `~/monad/scripts/claudebox-server.sh keepalive`; use `start` if the server is not already running.
3. If claudebox is not a Nomad member, rejoin with `~/monad/meta/bootstrap/join.sh 100.75.75.39 pro`.
4. Verify `nomad server members` shows `claudebox` `alive` and a cluster leader exists again.
5. Run `~/monad/meta/agent/ensure-engines.sh` so engine metadata is re-advertised after rejoin.

Avoid destructive actions: no data wipes, no force-pushes, and no cluster-wide restarts.
