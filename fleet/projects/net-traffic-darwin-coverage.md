---
slug: net-traffic-darwin-coverage
status: building
owner: agent-builder-3-053516
updated: 2026-06-03
priority: 6
---
# net-traffic publisher coverage for non-linux nodes → complete the tournament

**Follow-on to [dashboard-cluster-graph](dashboard-cluster-graph.md) (done).** The cluster
graph renders a directed **tournament** over the reachable nodes, but it reports
`stats.complete = false`: only the **5 linux** nodes run the `net-traffic` publisher
(constrained `kernel.name = linux`). A node only ever sees *its own* tx/rx to each peer —
no third node can observe peer-to-peer traffic — so the **single undetermined pair is
`windesk ↔ eliotts-mac-mini`** (the two non-publishers). That one missing edge keeps the
7-vertex tournament from being complete (20 edges instead of C(7,2)=21).

**Goal:** put a `net-traffic` publisher on at least **one** of the two non-linux nodes so
that pair becomes determinable and the dashboard tournament reaches `complete = true` (21
edges, full score sequence / king / Hamiltonian path over all 7 vertices).

## Plan
- Start with **eliotts-mac-mini** (`kernel.name = darwin`, `driver.raw_exec = 1`): macOS
  ships `python3`, so the existing Python publisher in `jobs/net-traffic.hcl` is reusable
  almost verbatim — only the platform constraint and the tailscale binary path differ.
- Ship it as a **separate** job `jobs/net-traffic-darwin.hcl` (system job, `kernel.name =
  darwin`) so the linux publisher is untouched and this is independently
  deployable/undeployable. Same var schema `fleet/net-traffic/<node>` the dashboard already
  reads — **no dashboard / server.py change needed**.
- Robust tailscale lookup for macOS: try `tailscale`, `/usr/local/bin/tailscale`,
  `/Applications/Tailscale.app/Contents/MacOS/Tailscale`.
- (Stretch) a Windows/PowerShell variant for windesk if the darwin node proves too flaky.

## Acceptance
- A `net-traffic` publisher runs on a non-linux node and writes `fleet/net-traffic/<node>`
  with the same schema (node, ip, host, peer_count, ts, peers_json).
- The dashboard `/api/state.graph` shows the new node among `publishers` and reports
  `stats.complete = true` with 21 edges over the 7 active vertices (or documents why a node
  is genuinely unreachable and marks blocked with the diagnostic).
- Read-only / resource-limited / reversible; committed (job in `jobs/`), project Log updated,
  peers told.

## Notes
- Pure read-only: runs `tailscale status --json` (local view) and writes one Nomad var.
- eliotts-mac-mini is noted "flaky on Tailscale" in the roster — if its tailscale view is
  unavailable the publisher self-reports it; fall back to the windesk variant.
