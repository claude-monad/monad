# Fleet Backlog

The fleet continuously works this list. Each item is a file in `fleet/projects/<slug>.md`
(the claim unit — see `fleet/PROTOCOL.md`). This is the human-readable index; the project
files hold the live `status`/`owner`.

Priority order (top = next). Pick the highest `todo` you can do on a node you can reach.

| Pri | Project | Why | Status |
|----:|---------|-----|--------|
| 1 | [shared-registry](projects/shared-registry.md) | a tailnet-wide container registry so images run on every node (not just oraclebox1's localhost:5000) — unblocks everything below | done (100.78.218.70:5000) |
| 2 | [multiarch-agent-image](projects/multiarch-agent-image.md) | build monad-agent-mesh for amd64+arm64 so v1410-1 & bigo-server can run mesh agents → maintenance agents on the mesh everywhere | done (amd64 verified on v1410-1; image multi-arch in registry) |
| 6 | [bigo-server-registry-trust](projects/bigo-server-registry-trust.md) | bigo-server dockerd rejects the insecure shared registry (HTTP→HTTPS error) so it can't pull shared images | done (bigo-server trusts 100.78.218.70:5000; pull verified) |
| 7 | [amd64-maintenance-mesh](projects/amd64-maintenance-mesh.md) | amd64 maintenance agents idle ("no monad checkout") + never join the mesh; provision repo + portable cred path | done (agent-maint-bigo-server + agent-maint-V1410-1 on mesh via alloc-local clone) |
| 3 | [cluster-dashboard](projects/cluster-dashboard.md) | a web app showing fleet state: nodes, jobs, mesh peers, events, this backlog | done (100.78.218.70:8088) |
| 4 | [shared-postgres](projects/shared-postgres.md) | a Postgres the fleet can use for shared state & coordination | done (100.78.218.70:5432) |
| 5 | [fleet-foreman-service](projects/fleet-foreman-service.md) | make the foreman a standing service that keeps builders working this backlog | done (job fleet-foreman on oraclebox1; var fleet/status) |
| 8 | [postgres-backup](projects/postgres-backup.md) | automated retained backups for the shared Postgres — today its only copy is the live bind-mount on bigo-server | done (job postgres-backup; daily 04:00 UTC → /opt/monad-postgres-backups on bigo-server) |
| 9 | [agent-mesh-cred-portability](projects/agent-mesh-cred-portability.md) | node-portable cred mounts so agent-mesh runs off-oraclebox1, + engine creds for amd64 maintenance agents (they're mesh-present but engine-less) | done (all 3 acceptance items met: mesh off-oraclebox1 via #15, amd64 maintenance engines exit_code=0 via #18) |
| 10 | [dashboard-live-events](projects/dashboard-live-events.md) | stream fleet events into the dashboard without polling the full cluster state | done (SSE at 100.78.218.70:8088/api/events/stream) |
| 11 | [amd64-agent-checkout-sync](projects/amd64-agent-checkout-sync.md) | safely fast-forward stale host monad checkouts on amd64 nodes so agent jobs see current repo code | blocked (ROOT CAUSE found: both checkouts track WRONG origin eliottcassidy2000/monad@4f6a4dc, not eliott-monad/monad → ff-pull impossible; needs owner OK for destructive re-point+reset. diag in nomad vars fleet/checkout-diag/<node>) |
| 12 | [amd64-agent-uid-image](projects/amd64-agent-uid-image.md) | per-host uid variants of the agent-mesh image so amd64 nodes' mode-600 creds are readable (blocker #2 of #9) | done (registry tags uid1000/uid1001/latest verified; node meta agent_uid wired) |
| 13 | [agent-checkout-health](projects/agent-checkout-health.md) | standing low-noise monitor that flags agent nodes whose host monad checkout tracks the wrong remote / is missing key agent files (the silent failure behind #11) | done (periodic job agent-checkout-health; vars fleet/checkout-health/<node>; every 6h) |
| 14 | [fleet-foreman-status-detail](projects/fleet-foreman-status-detail.md) | make the standing foreman publish active/blocked project ownership details in `fleet/status` so handoffs and orphaned work are visible without reading every project file | done (fleet/status has active_projects + blocked_projects) |
| 15 | [agent-mesh-alloc-clone](projects/agent-mesh-alloc-clone.md) | make agent-mesh fresh-clone the repo per-alloc (like fleet-builder) instead of mounting the stale wrong-origin host checkout — non-destructive path that unblocks briefed mesh agents on amd64 without the owner-gated re-point (#11) | done (verified: briefed dispatch runs healthy on V1410-1, exit 0, correct origin) |
| 16 | [dashboard-foreman-status](projects/dashboard-foreman-status.md) | show the foreman's `fleet/status` detail on the dashboard so handoffs are visible without CLI access | done (Fleet Foreman section + /api/state.foreman_status live at 100.78.218.70:8088) |
| 17 | [registry-health](projects/registry-health.md) | read-only catalog + disk-growth monitor for the keystone shared registry (100.78.218.70:5000) so a filling registry disk is caught before it breaks cluster-wide pulls | done (periodic job registry-health on bigo-server, every 6h; var fleet/registry-health) |
| 18 | [amd64-maintenance-engine](projects/amd64-maintenance-engine.md) | make amd64 maintenance-agents (V1410-1, bigo-server) run the engine as a non-root credentialed user so they complete self-passes + drain queues (closes #9 item 2). Measured state captured | done (bigo-server last exit_code=0 as user bigo; V1410-1 drained stuck task rc=0 as user e; oraclebox1 unchanged) |
| 19 | [events-log-union-merge](projects/events-log-union-merge.md) | avoid recurring manual merge conflicts when multiple agents append independent fleet events to `logs/events.jsonl` | done (`merge=union` in `.gitattributes`) |
| 20 | [raft-quorum-health](projects/raft-quorum-health.md) | low-noise monitor of the Nomad control-plane quorum margin — flags a fragile "only 2 voters / zero fault tolerance" state *before* it tips into a leaderless outage (the 2026-06-02 outage that blocked all deploys) | done (periodic job raft-quorum-health on oraclebox1, every 15m; var fleet/raft-health) |

**Adding work:** any agent (or the owner) can drop a new `fleet/projects/<slug>.md` with
`status: todo` and add a row here. The fleet will pick it up. Improvements to existing tools
are welcome as new projects (e.g. "add auth to the dashboard").
