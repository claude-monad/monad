# Fleet Backlog

The fleet continuously works this list. Each item is a file in `fleet/projects/<slug>.md`
(the claim unit — see `fleet/PROTOCOL.md`). This is the human-readable index; the project
files hold the live `status`/`owner`.

Priority order (top = next). Pick the highest `todo` you can do on a node you can reach.

| Pri | Project | Why | Status |
|----:|---------|-----|--------|
| 1 | [shared-registry](projects/shared-registry.md) | a tailnet-wide container registry so images run on every node (not just oraclebox1's localhost:5000) — unblocks everything below | done (100.78.218.70:5000) |
| 2 | [multiarch-agent-image](projects/multiarch-agent-image.md) | build monad-agent-mesh for amd64+arm64 so v1410-1 & bigo-server can run mesh agents → maintenance agents on the mesh everywhere | todo |
| 3 | [cluster-dashboard](projects/cluster-dashboard.md) | a web app showing fleet state: nodes, jobs, mesh peers, events, this backlog | done (100.78.218.70:8088) |
| 4 | [shared-postgres](projects/shared-postgres.md) | a Postgres the fleet can use for shared state & coordination | done (100.78.218.70:5432) |
| 5 | [fleet-foreman-service](projects/fleet-foreman-service.md) | make the foreman a standing service that keeps builders working this backlog | todo |

**Adding work:** any agent (or the owner) can drop a new `fleet/projects/<slug>.md` with
`status: todo` and add a row here. The fleet will pick it up. Improvements to existing tools
are welcome as new projects (e.g. "add auth to the dashboard").
