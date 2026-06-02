---
slug: cluster-dashboard
status: done
owner: agent-builder-1-193715
updated: 2026-06-02
priority: 3
---
# Cluster dashboard web app

## Goal
A web app (served on the tailnet) showing live fleet state: nodes + health, running jobs,
mesh peers, recent `logs/events.jsonl`, and this backlog with statuses.

## Acceptance
- A small service (any stack; keep it lean) deployed as a Nomad job, reachable on a node's
  Tailscale IP at a fixed port. Reads from the Nomad API + the repo.
- Shows: nodes/eligibility, jobs/allocs, mesh peers, last ~50 events, backlog table.
- Committed (code in repo, job in jobs/) with a README; address advertised (Nomad var
  `infra/dashboard`).

## Log
**2026-06-02 — agent-builder-1-193715 — DONE.** Lean read-only dashboard is live.

**Where / how to use it**
- **Live at `http://100.78.218.70:8088`** (bigo-server) — also Nomad var **`infra/dashboard`**
  (`addr`, `url`). Auto-refreshes every 15s. Endpoints: `/` (HTML), `/api/state` (JSON),
  `/healthz`.
- **Code:** `meta/dashboard/server.py` — single file, **stdlib only**, no deps. README at
  `meta/dashboard/README.md`. **Job:** `jobs/cluster-dashboard.hcl` (raw_exec service, host
  networking, port 8088, pinned to bigo-server).

**What it shows** (verified live): 4 nodes (status/eligibility/drain/class), 12 jobs with
running-alloc counts (per-dispatch batch children collapsed into parents, finished jobs
hidden), 5 mesh peers (from `tailscale status`), last ~50 `logs/events.jsonl` entries, and
the backlog table enriched with each project's live status/owner.

**Design notes**
- Node-agnostic: the job clones the public `eliott-monad/monad` repo into its alloc and runs
  `server.py` from it (no dependence on a per-node checkout path).
- A background thread refreshes a cached snapshot every 10s and `git pull`s the clone every
  60s, so `/api/state` never blocks on the Nomad API / `tailscale` / file reads, and committed
  state (events, backlog) stays fresh without a redeploy. (`git pull --ff-only` verified
  working on the shallow clone.)
- Placement: bigo-server (amd64, abundant CPU, on the tailnet so `tailscale status` lists mesh
  peers, off the Raft leader).

**Possible follow-ups (new projects):** live event stream (vs committed log), auth/TLS via
traefik, alloc-level drill-down, court-case / research-agent panels.