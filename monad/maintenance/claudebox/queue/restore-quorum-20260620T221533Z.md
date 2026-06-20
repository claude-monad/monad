# claudebox: restore Nomad quorum

Filed by: eliotts-mac-mini cluster-health sweep 2026-06-20T22:15:33Z.

Current state:
- `nomad server members` via `100.75.75.39` shows only `V1410-1` alive and returns `No cluster leader`.
- `nomad node status` and `nomad job status maintenance-agent` fail with `500 No cluster leader`.
- `tailscale ping 100.87.219.108` from eliotts-mac-mini times out; `oraclebox1` is also unreachable, so either voter recovery restores quorum.
- Existing open escalation: `meta/coordination/tasks/t-0185.json`.

Smallest safe recovery when this machine is reachable:
1. Restore claudebox power/network/Tailscale.
2. Run `~/monad/scripts/claudebox-server.sh keepalive`; use `start` if it is not already running.
3. If it is not a Nomad member, rejoin with `~/monad/meta/bootstrap/join.sh 100.75.75.39 pro server`.
4. Verify `nomad server members` shows a leader and at least two alive voters, then verify node readiness and `maintenance-agent` coverage.
