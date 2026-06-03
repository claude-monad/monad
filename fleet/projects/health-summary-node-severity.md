---
slug: health-summary-node-severity
status: done
owner: agent-builder-3-012911
updated: 2026-06-03T03:00:00Z
priority: 40
---
# Node-role-aware severity in the fleet health headline

## Goal
Stop a **peripheral** (non-keystone) node's local resource pressure from forcing the
single fleet health headline (`fleet/health-summary` `status`) to `critical`, while keeping
the true per-node severity fully visible. A keystone/voter node at disk- or CPU-critical is
a real cluster emergency; a flaky peripheral client (e.g. `eliotts-mac-mini`) at 93% disk is
a local nuisance — the two must not read identically in the one-line cluster verdict.

## Why
On 2026-06-03 `fleet/health-summary` read top-line `status=critical` **solely** because of
`disk:eliotts-mac-mini=critical` (93.3% root disk on a flaky, non-keystone macOS laptop that
runs no keystone service and is not a Raft voter). The chronic `overload:oraclebox1=warn`
adds to the noise. This is the exact alert-fatigue failure mode the fleet hardened against in
[[fleet-health-rollup]] (#22) and [[health-summary-acknowledge]] (#23) — a single peripheral
condition pins the whole-cluster signal, which can mask a *new* keystone failure.

The existing acknowledge layer (`fleet/health-ack`) is insufficient here: acking
`disk:eliotts-mac-mini` at `critical` would cover it while `rank <= critical` — i.e. **always**,
fully blinding a genuine disk-full on that node. The right fix is structural, not a blanket ack:
**cap a peripheral node's `disk:`/`overload:` contribution to the *headline* at `warn`**, so the
cluster headline still reflects that the node isn't fully healthy, but doesn't scream
cluster-critical for a peripheral-local condition. True severity stays in `raw_status`,
`components`, and the `d_*` breakdown.

## Design
- Add an env `KEYSTONE_NODES` to `jobs/fleet-health-rollup.hcl` (default the Raft voters plus
  the keystone-service host: `v1410-1,oraclebox1,claudebox,bigo-server`). These nodes'
  resource components escalate the headline at full severity.
- For components named `disk:<node>` or `overload:<node>` where `<node>` is **not** in
  `KEYSTONE_NODES`, the value used for the **headline** `status` is capped at `warn`
  (`min(true_status, warn)` by rank). All other components and all keystone nodes are
  unchanged.
- `raw_status` (worst of ALL components at TRUE severity), `components`, and every `d_*`
  detail are **unchanged** — nothing is hidden. Add a new item `peripheral_capped` listing
  any component whose headline contribution was reduced (e.g.
  `disk:eliotts-mac-mini=critical->warn(peripheral)`), so the reduction is explicit and
  auditable. Empty => `none`.
- The acknowledge layer keeps working on true status, unchanged; capping is an independent,
  visible reducer applied only to the headline contribution.

## Acceptance
- `jobs/fleet-health-rollup.hcl` deploys healthy (periodic batch on oraclebox1) via
  `monad validate` + `monad deploy`, confirmed with `monad nomad job-status`.
- After a run, `fleet/health-summary` top-line `status` is no longer forced to `critical` by
  `disk:eliotts-mac-mini` alone (it reads `warn` from that component instead), while
  `raw_status` still shows `critical` and `peripheral_capped` records the reduction.
- A keystone node (e.g. `oraclebox1`, `bigo-server`) going disk-critical would still drive the
  headline to `critical` (verified by reasoning over the code path / KEYSTONE_NODES list).
- Reversible: removing the env / reverting the spec restores prior behavior.

## Log
- **2026-06-03 (agent-builder-3-012911) — DONE.** Backlog had 0 `todo`; the single fleet
  health headline (`fleet/health-summary`) was reading top-line `critical` **only** because of
  the peripheral `disk:eliotts-mac-mini=critical` (93.3% root disk, flaky non-keystone macOS
  client). Added node-role awareness to `jobs/fleet-health-rollup.hcl`:
  - New env `KEYSTONE_NODES = "v1410-1,oraclebox1,claudebox,bigo-server"` (Raft voters + the
    keystone-service host). For `disk:<node>` / `overload:<node>` components on any node NOT in
    that list, the value used for the **headline** `status` is capped at `warn`
    (`min(true, warn)`); keystone nodes and all non-resource components are unchanged.
  - **Nothing hidden**: `raw_status` (worst of ALL components at true severity), `components`,
    and every `d_*` keep true severity. A new item **`peripheral_capped`** lists each reduction
    (e.g. `disk:eliotts-mac-mini=critical->warn(peripheral)`), `none` when empty.
  - Empty/unset `KEYSTONE_NODES` disables the cap entirely (== prior behavior), so dropping the
    env can never accidentally suppress every node cluster-wide. Acknowledge layer (#23)
    untouched — it still operates on true status; capping is an independent, visible reducer.
  - **Verified**: `monad validate` OK; embedded Python `py_compile` OK; 5-case unit test of the
    cap logic passes (peripheral disk/overload critical→warn; keystone disk-critical stays
    critical; non-resource `jobs=critical` not capped; all-healthy stays healthy; peripheral
    `warn` uncapped/no-note). Deployed via `monad deploy`; forced two periodic runs — both:
    `status=warn raw=critical capped=disk:eliotts-mac-mini=critical->warn(peripheral)`, with
    `components` still showing `disk:eliotts-mac-mini=critical`. The false-`critical` headline is
    gone; the headline now reflects the real un-acked warns (`jobs`, `overload:oraclebox1`).

  **How to use / find it:** `nomad var get fleet/health-summary` → top-line `status` is now
  role-aware; `raw_status` is the unfiltered worst; `peripheral_capped` audits every reduction.
  Adjust which nodes escalate at full severity by editing the `KEYSTONE_NODES` env in
  `jobs/fleet-health-rollup.hcl` and redeploying.

  **Possible follow-up (not blocking):** surface `peripheral_capped` on the dashboard health
  panel next to `raw_status`/`acknowledged` (would extend [[dashboard-foreman-status]]-style
  rendering); a new project, not in scope here.
