# Cluster dashboard

A lean, **read-only** web view of the Monad fleet, served on the tailnet.

- **Live at:** `http://100.78.218.70:8088` (bigo-server) — also in Nomad var `infra/dashboard`.
- **Job:** `jobs/cluster-dashboard.hcl` (raw_exec service, host networking, port 8088).
- **Code:** `meta/dashboard/server.py` — single file, **stdlib only** (no dependencies).

## What it shows
- **Cluster graph (node-health tournament)** — an interactive SVG diagram of the cluster
  rendered as a **tournament** (the math the cluster exists to do): each node is a vertex
  colored by its `fleet/health-summary` verdict; between every measured node pair there is
  **one directed edge**, pointing from whichever node sent **more** tailnet traffic to the
  other (the pair "winner"), with **thickness = |net| bytes**. Click a node to inspect its
  jobs/allocs, per-node health components, and live cpu/mem/disk %; hover an edge for the
  pairwise tx/rx + net. Below the graph: out-degree **score sequence**, **king(s)** (2-step
  dominators), and a **Hamiltonian path** when the tournament is complete. Edge direction
  data comes from the per-node `net-traffic` publishers (see below).
- **Nodes** — status / scheduling eligibility / drain / class (Nomad `/v1/nodes`).
- **Jobs** — meaningful jobs with a running-alloc count; per-dispatch batch children are
  collapsed into their parent and finished jobs are hidden (Nomad `/v1/jobs` + `/v1/allocations`).
- **Mesh peers** — tailnet hosts named `agent-*`, best-effort from `tailscale status --json`
  on the host (empty if the tailscale CLI isn't available there).
- **Backlog** — `fleet/BACKLOG.md` rows enriched with each project's live `status`/`owner`.
- **Recent events** — last ~50 lines of `logs/events.jsonl`, newest first.
- **Live event stream** — the Recent events panel subscribes to a focused SSE feed so it
  updates independently from the full state snapshot.

### The `net-traffic` publishers (cluster-graph edge data)
The pairwise traffic that orients the tournament is only visible from each node's *local*
`tailscale status --json` view, so a `system` job (`jobs/net-traffic.hcl`, raw_exec, on every
linux node) runs there and writes its per-peer tx/rx counters to the Nomad var
`fleet/net-traffic/<node>` every 60s. A single node's view of a peer already carries **both**
directions (tx = self→peer, rx = peer→self), so even one publisher yields edges; with every
linux node publishing, the matrix is cross-checked. The dashboard reads all those vars and
assembles `state.graph`. Nodes without a publisher (windesk, eliotts-mac-mini) still appear as
vertices and get edges via other nodes' views — only the one pair where *neither* publishes
(windesk↔mac-mini) is unmeasurable, so the tournament is reported as "partial" until then.

## How it works
The job clones the public `eliott-monad/monad` repo into its alloc dir and runs `server.py`
from it. A background thread `git pull`s that clone every `REFRESH_SECS` (60s) so committed
state (events, backlog, project statuses) stays current without a redeploy. Nomad data is
read from the cached dashboard state. The page refreshes full state every 30s, while recent
events update from a Server-Sent Events stream every few seconds.

## Endpoints
- `GET /`            — the HTML dashboard
- `GET /api/state`   — JSON snapshot (nodes, jobs, peers, events, backlog, `graph`)
  - `state.graph` = `{available, publishers, convention, nodes[], edges[], stats}`; each
    edge is `{src, dst, src_to_dst, dst_to_src, net, total}` (bytes); `stats` carries
    `out_degree`, `score_sequence`, `kings`, `complete`, `hamiltonian_path`.
- `GET /api/events`  — JSON array of recent fleet events
- `GET /api/events/stream` — Server-Sent Events feed for recent fleet events
- `GET /healthz`     — liveness (used by the Nomad health check)

## Config (env)
| var | default | meaning |
|-----|---------|---------|
| `NOMAD_ADDR` | `http://100.75.75.39:4646` | Nomad API base |
| `DASH_PORT` | `8088` | listen port |
| `REPO_DIR` | repo root | where to read repo files / git-pull |
| `REFRESH_SECS` | `60` | repo git-pull interval |
| `EVENT_STREAM_SECS` | `5` | event-stream file check interval |

## Run locally
```bash
NOMAD_ADDR=http://100.125.210.126:4646 REPO_DIR=/path/to/monad python3 meta/dashboard/server.py
# then open http://localhost:8088
```
