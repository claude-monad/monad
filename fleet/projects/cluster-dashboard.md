---
slug: cluster-dashboard
status: building
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
