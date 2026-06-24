---
slug: math-worker-readonly-views
status: building
owner: codex
updated: 2026-06-24T07:06:57Z
priority: 1
---

# math-worker-readonly-views

## Owner Request
Expose a read-only view of every active math worker at a stable Tailscale-reachable address,
so the owner can monitor cluster researchers without needing to discover Nomad allocation IDs,
SSH into nodes, or risk accidentally sending input to a running session.

## Desired State

- The dashboard lists each math worker/session with node name, role, engine, start time,
  timeout budget, current state, repo checkout path, and links to read-only output.
- Each worker has a read-only tailnet URL, either as a per-node service
  (`http://<node-tailnet>:<port>/workers/<id>`) or a central dashboard proxy backed by Nomad
  allocation logs.
- The read-only view can tail stdout/stderr and show the last Poke Forum comment target, but
  exposes no prompt box, shell, kill button, token, credential, env dump, or writable action.
- Worker URLs should prefer Tailscale private addresses and must not require Funnel. The owner
  can still reach them from iOS/Desktop when those clients are on the tailnet; Funnel is only
  for deliberate public exposure, not the default monitoring path.
- The view should cover Nomad jobs on all cluster nodes, not just this Mac heartbeat.

## Acceptance

- Commit and deploy a monitoring surface that discovers running math jobs from Nomad
  (`math-explore*`, `math-researcher`, `math-reviewer`, `math-quick-compute`,
  `math-pro-sessions`, `dual-engine-math-test`, and formalizer jobs where relevant).
- Link that surface from `cluster-dashboard` and publish its canonical URL in a Nomad var such
  as `infra/math-worker-views`.
- Confirm at least one live worker can be viewed read-only from a Tailscale address.
- Document the owner command/path for CLI monitoring, including `nomad job status`,
  `nomad alloc logs`, and the dashboard URL.

## Implementation Notes

- Reuse `meta/dashboard/server.py` or add a small sibling service rather than exposing
  `meta/codex-tui/server.py`, because the TUI is interactive by design.
- Nomad already has enough source data for a first cut: job status, allocation metadata,
  node name, task state, and logs via the Nomad API.
- If per-node viewers are added later, bind only to the tailnet interface or host loopback
  behind an authenticated tailnet proxy; keep the first version read-only and boring.

## Log

- 2026-06-24 — Owner requested cluster-wide read-only worker visibility at Tailscale addresses
  while moving math forum jobs to a 20-minute cadence with at least 40-minute run budgets.
- 2026-06-24 — Implemented first dashboard pass: `meta/dashboard/server.py` now discovers
  active/recent math allocations across Nomad and exposes bounded read-only stdout/stderr tails
  via `/api/math/log`; the page has a Math workers panel that auto-refreshes selected logs
  every 5 seconds. Local API test successfully read live `math-formalizer` Codex output from
  an `eliotts-mac-mini` allocation through the Nomad log API. Remaining deployment check:
  verify the dashboard's tailnet URL is reachable from owner devices.
