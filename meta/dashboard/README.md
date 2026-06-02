# Cluster dashboard

A lean, **read-only** web view of the Monad fleet, served on the tailnet.

- **Live at:** `http://100.78.218.70:8088` (bigo-server) — also in Nomad var `infra/dashboard`.
- **Job:** `jobs/cluster-dashboard.hcl` (raw_exec service, host networking, port 8088).
- **Code:** `meta/dashboard/server.py` — single file, **stdlib only** (no dependencies).

## What it shows
- **Nodes** — status / scheduling eligibility / drain / class (Nomad `/v1/nodes`).
- **Jobs** — meaningful jobs with a running-alloc count; per-dispatch batch children are
  collapsed into their parent and finished jobs are hidden (Nomad `/v1/jobs` + `/v1/allocations`).
- **Mesh peers** — tailnet hosts named `agent-*`, best-effort from `tailscale status --json`
  on the host (empty if the tailscale CLI isn't available there).
- **Backlog** — `fleet/BACKLOG.md` rows enriched with each project's live `status`/`owner`.
- **Recent events** — last ~50 lines of `logs/events.jsonl`, newest first.

## How it works
The job clones the public `eliott-monad/monad` repo into its alloc dir and runs `server.py`
from it. A background thread `git pull`s that clone every `REFRESH_SECS` (60s) so committed
state (events, backlog, project statuses) stays current without a redeploy. Nomad data is
read live from the API each request. The page auto-refreshes every 15s.

## Endpoints
- `GET /`            — the HTML dashboard
- `GET /api/state`   — JSON snapshot (nodes, jobs, peers, events, backlog)
- `GET /healthz`     — liveness (used by the Nomad health check)

## Config (env)
| var | default | meaning |
|-----|---------|---------|
| `NOMAD_ADDR` | `http://100.75.75.39:4646` | Nomad API base |
| `DASH_PORT` | `8088` | listen port |
| `REPO_DIR` | repo root | where to read repo files / git-pull |
| `REFRESH_SECS` | `60` | repo git-pull interval |

## Run locally
```bash
NOMAD_ADDR=http://100.125.210.126:4646 REPO_DIR=/path/to/monad python3 meta/dashboard/server.py
# then open http://localhost:8088
```
