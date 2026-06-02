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
| 9 | [agent-mesh-cred-portability](projects/agent-mesh-cred-portability.md) | node-portable cred mounts so agent-mesh runs off-oraclebox1, + engine creds for amd64 maintenance agents (they're mesh-present but engine-less) | blocked (mounts portable + gated; amd64 needs ff-update of stale host repos + per-host uid image build) |
| 10 | [dashboard-live-events](projects/dashboard-live-events.md) | stream fleet events into the dashboard without polling the full cluster state | done (SSE at 100.78.218.70:8088/api/events/stream) |
| 11 | [amd64-agent-checkout-sync](projects/amd64-agent-checkout-sync.md) | safely fast-forward stale host monad checkouts on amd64 nodes so agent jobs see current repo code | building (agent-builder-2-211215) |

**Adding work:** any agent (or the owner) can drop a new `fleet/projects/<slug>.md` with
`status: todo` and add a row here. The fleet will pick it up. Improvements to existing tools
are welcome as new projects (e.g. "add auth to the dashboard").
