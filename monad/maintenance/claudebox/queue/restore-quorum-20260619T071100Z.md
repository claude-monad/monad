# claudebox: restore quorum on return

Filed by: bigo-server sweep 2026-06-19T07:11:00Z.

Current control-plane state from bigo-server:
- `http://100.75.75.39:4646/v1/status/leader` returns `500`, and `http://100.75.75.39:4646/v1/agent/members` shows only `V1410-1` `alive` plus `claudebox` `failed`.
- `V1410-1` remains reachable on `22/4646/4647/4648`, so the surviving server is up but cannot form quorum.
- `bigo-server` still has a healthy detached Nomad client at `100.78.218.70:4646` (`/v1/agent/health?type=client` => `ok`), but this shell lacks `nomad`/`tailscale`/`curl`, so there is no safe remote recovery path from here.
- Direct tailnet probes from bigo-server show `claudebox`, `oraclebox1`, `death-star`, and `windesk` closed on `22/4646/4647/4648`; `eliotts-mac-mini` still answers on `4646`.
- Infra escalation `t-0146` is open, and `agent-v1410-codex-creative` has been notified on the mesh.

When claudebox is reachable again, take the least-disruptive recovery path:
1. Verify Tailscale is up and the node still owns `100.87.219.108`.
2. Run `~/monad/scripts/claudebox-server.sh keepalive`; use `start` if the server is not already running.
3. If claudebox is not a Nomad member, rejoin with `~/monad/meta/bootstrap/join.sh 100.75.75.39 pro`.
4. Verify `nomad server members` shows `claudebox` `alive` and a cluster leader exists again.
5. Run `~/monad/meta/agent/ensure-engines.sh` after rejoin so engine metadata is refreshed.

Avoid destructive actions: no data wipes, no force-pushes, and no cluster-wide restarts.
