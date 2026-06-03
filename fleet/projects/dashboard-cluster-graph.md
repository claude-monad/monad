---
slug: dashboard-cluster-graph
status: done
owner: agent-builder-3-044339
updated: 2026-06-03
priority: 5
---
# Dashboard: interactive cluster graph (a node-health "tournament")

**Owner request (2026-06-02).** Add an **interactive diagram of the cluster** to the dashboard
(`meta/dashboard/server.py`, served by `cluster-dashboard` on bigo-server **:8088**). It should
show, at a glance and live:
- **each node** as a vertex, colored by its **health** (fold in `fleet/health-summary`
  components per node: `disk:<node>`, `overload:<node>`, `maintenance:<node>`, raft voter
  status, etc. — green/yellow/red);
- **the jobs/allocs on each node** (the running allocs Nomad reports per node — e.g. on
  hover/click, or as little satellites around the vertex), with their own health;
- **resources and jobs flowing from one node to another** as **edges** — traffic between
  nodes, dispatched/placed work, backup mirrors (e.g. the off-site backup flow
  bigo-server → death-star MinIO), mesh messages.

## The fun part: make it a tournament
The cluster's mission is tournament theory (complete directed graphs), so render the topology
as a **tournament**: between **every pair** of nodes draw **one directed edge**, oriented
**from the node that sends *more* traffic to the other** (the "winner" of that pair points at
the "loser", or vice-versa — pick one convention and label it). Net traffic decides direction;
edge weight/thickness can show the volume. With N reachable nodes that's a full tournament on N
vertices — a nice nod to the math the cluster exists to do. (Bonus if you surface tournament-y
stats the cluster already studies: each node's **out-degree / score sequence**, whether the
orientation has a Hamiltonian path, who the "king" node is.)

## Data sources (all already reachable from the dashboard)
- **Per-pair traffic for edge direction:** `tailscale status --json` already parsed in
  `mesh_peers()` — each peer carries **`TxBytes` / `RxBytes`** from the local node's view.
  To get a cluster-wide pairwise matrix you need each node's view, not just the dashboard
  host's; options: (a) have each node publish its `tailscale status --json` tx/rx to a Nomad
  var (e.g. `fleet/net-traffic/<node>`) on a short interval and have the dashboard assemble the
  matrix, or (b) start from the dashboard-host-relative edges and note the limitation. Net =
  `tx(A→B) − tx(B→A)`; orient the edge toward the larger sender; |net| → thickness.
- **Nodes + jobs/allocs + health-per-node:** the Nomad API helpers already in `server.py`
  (`nodes()`, `jobs()`, `node_resources()`) plus `health_summary()` (`fleet/health-summary`).
- **Other flows (optional edges):** dispatched/placed work (alloc node placement), the backup
  mirror flow (`fleet/offsite-backup`), mesh messages.

## Acceptance
- The dashboard (`http://100.78.218.70:8088`, var `infra/dashboard`) gains an **interactive**
  cluster graph: nodes colored by health, their jobs/allocs visible, directed edges between
  node pairs oriented by who sends more traffic (the tournament), edge weight = traffic volume.
  Interactive = at least hover/click to inspect a node (its jobs, resource %, health
  components) and an edge (the pairwise tx/rx + net). Auto-refreshes like the rest of the page.
- Keep the dashboard's house style: **lean, few/no deps** (`server.py` is stdlib-only today).
  A small vendored/CDN graph lib (e.g. a force-directed SVG/canvas) is fine if it stays a
  single static asset; prefer something that degrades gracefully if offline.
- New/updated data exposed under `/api/state` (e.g. `state.graph = {nodes, edges}`) so the
  topology is machine-readable too. If you add a per-node traffic publisher, ship it as a small
  read-only periodic Nomad job in `jobs/` with resource limits (per fleet protocol).
- Committed (code in repo, any new job in `jobs/`), README updated, address advertised, peers
  told. Decide placement of any new publisher with peers (it must run on every node it measures).

## Notes
- Read-only / non-destructive: this only *reads* Nomad + tailscale state and *renders* it.
- If a full pairwise matrix needs a per-node publisher, that's a clean sub-step — land the
  graph against dashboard-host-relative edges first, then upgrade to the full tournament.

## Log
- **2026-06-03 (agent-builder-3-044339): DONE.** The dashboard
  (`http://100.78.218.70:8088`, var `infra/dashboard`) now has an **interactive cluster
  graph rendered as a tournament** at the top of the page.
  - **Edge data:** new `system` job `jobs/net-traffic.hcl` (raw_exec, linux + raw_exec
    constraint) runs on every linux node and publishes its local `tailscale status --json`
    per-peer tx/rx to the Nomad var `fleet/net-traffic/<node>` every 60s (cpu50/mem64,
    read-only). A single node's view of a peer carries BOTH directions (tx=self→peer,
    rx=peer→self), so the dashboard assembles a cross-checked pairwise matrix from the 5
    linux publishers (V1410-1, bigo-server, claudebox, death-star, oraclebox1).
  - **Graph (`meta/dashboard/server.py`):** `cluster_graph()` builds `state.graph` =
    `{available, publishers, convention, nodes[], edges[], stats}`. Nodes colored by their
    `fleet/health-summary` per-node verdict (disk:/overload:/maintenance:/checkout:…);
    between every measured pair, ONE directed edge oriented toward the heavier sender,
    thickness = |net| bytes. **Interactive:** click a node → side panel with its jobs/allocs,
    health components, live cpu/mem/disk %; hover an edge → pairwise tx/rx + net tooltip.
    Auto-refreshes with the 30s page load. Stdlib-only, inline SVG (no new deps).
  - **Tournament stats** (the fun part): out-degree **score sequence**, **king(s)** (2-step
    dominators), and a validated **Hamiltonian path**. Live now: 7 vertices, 20/21 edges
    (only windesk↔mac-mini unmeasurable since neither publishes → reported "partial"),
    score sequence [4,4,3,3,3,2,1].
  - **To find it:** open the dashboard → top "Cluster graph" panel; machine-readable at
    `GET /api/state` → `.graph`. Per-node traffic vars: `nomad var get fleet/net-traffic/<node>`.
  - **Future:** add windesk/mac-mini publishers (Windows/macOS shell variants) to complete
    the tournament; optionally overlay non-traffic edges (backup-mirror flow, dispatched work).
