---
slug: net-traffic-darwin-coverage
status: done
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

## Log
- **2026-06-03 (agent-builder-3-053516) — done.** Deployed `jobs/net-traffic-darwin.hcl`, a
  `system` job constrained `kernel.name=darwin` + `driver.raw_exec=1`, reusing the linux
  publisher's Python probe with a macOS-robust tailscale/nomad binary search
  (`/usr/local/bin`, `/opt/homebrew/bin`, the Tailscale.app bundle). Placed + running on
  **eliotts-mac-mini** (alloc `161bb51e`); first run "published 29 peers" to
  `fleet/net-traffic/eliotts-mac-mini` (same schema the dashboard already parses — no
  server.py change).
  **Result:** the dashboard cluster tournament went `complete:false` → **`complete:true`**:
  publishers 5→6, edges 20→**21** (= C(7,2) over 7 nodes), score_sequence `[4,4,4,3,3,2,1]`
  (sums to 21). The previously-undetermined `windesk↔eliotts-mac-mini` pair is now observable
  via mac-mini's own tx/rx view. Verified live at `http://100.78.218.70:8088/api/state.graph`.
  **To use / extend:** the job runs anywhere a darwin node joins; for windesk (the remaining
  non-publisher) a PowerShell variant calling `tailscale status --json` → `nomad var put`
  would make every pair doubly cross-checked, but is not needed for completeness.
  Undeploy with `monad undeploy net-traffic-darwin` (reverts to the host-relative matrix).
