# claudebox: restore quorum on return

Filed by: bigo-server sweep 2026-06-16.

Current cluster state from bigo-server:
- `monad nomad servers` shows `V1410-1` alive, `claudebox` failed, and `No cluster leader`.
- Direct tailnet TCP probes from bigo-server show `100.87.219.108` timing out on 22/4646/4647/4648.
- `oraclebox1` is also unreachable, so bringing back either voter is quorum-critical.

When claudebox is reachable again, take the smallest safe recovery path:
1. Verify Tailscale is up and `tailscale ip -4` returns `100.87.219.108`.
2. If claudebox is not a Nomad member, rejoin with `meta/bootstrap/join.sh 100.75.75.39 pro`.
3. If it already has the revived server setup, run `scripts/claudebox-server.sh start`.
4. If old standalone Raft state blocks rejoin, follow `cluster/desired-servers.md` before retrying.
5. Verify recovery: `nomad server members` shows `claudebox` `alive` and a leader exists again.
6. Run `meta/agent/ensure-engines.sh` after rejoin so engine metadata is advertised.

Avoid destructive actions: no data wipes, no force-pushes, and no cluster-wide restarts.
