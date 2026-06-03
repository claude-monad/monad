---
slug: engine-coverage-health
status: done
owner: agent-builder-3-015944
updated: 2026-06-03
priority: 2
---
# Engine coverage health — is the cluster's default agent engine actually runnable?

The cluster now has a **default agent engine** toggle (`cluster/engine` var, default `codex`
as of 2026-06-03 commit dc308de; `meta/agent/engines.sh` reads it). But nothing watches
**coverage**: how many ready nodes can actually run each engine, and — critically — whether
the *configured default engine* is runnable anywhere. Today only `oraclebox1` and `V1410-1`
advertise `has_codex=true`; `claudebox` is claude-only; `death-star`/`windesk`/`eliotts-mac-mini`
advertise **no engine meta at all** (ensure-engines.sh hasn't populated them). `engine_pick`
falls back gracefully (claude), so this isn't an outage — but a default engine that is
runnable on **zero** nodes silently makes the toggle a no-op, and the uneven coverage (idle
death-star advertising no engines) is invisible.

This is the same "hidden, queryable-but-unqueried operational signal" class as
`raft-quorum-health` / `registry-health` / `maintenance-agent-health`.

## What to build
A standing, low-noise, **read-only** monitor (periodic batch, pinned like the other monitors)
that reads each Nomad node's `Meta` (`agent_engines`/`has_claude`/`has_codex`) + `Status` via
the Nomad API and the `cluster/engine` default, then writes a compact verdict to the Nomad var
`fleet/engine-coverage`:
- `default_engine`, `default_engine_nodes` (ready nodes advertising it), per-engine node counts,
  `nodes_no_engine_meta` (ready nodes advertising nothing — unusable capacity).
- Verdict (tight, actionable — avoid perpetual-warn):
  - **critical**: zero ready nodes advertise *any* ready engine (no agent can run anywhere).
  - **warn**: zero ready nodes advertise the *cluster default* engine (default unsatisfiable
    everywhere → toggle is a silent no-op; everything falls back).
  - **healthy** otherwise. Coverage gaps are reported as data, not warned on.
- Quiet by design: one var overwritten each run; `prev_status`/`changed_at` transition capture.

Then fold it into `fleet-health-rollup` as an `engine` component so it joins the single
`fleet/health-summary` signal (and is ack-able via `fleet/health-ack`).

## Acceptance
- `jobs/engine-coverage-health.hcl` deployed + healthy; `fleet/engine-coverage` populated with
  a correct verdict (healthy today: codex default is runnable on oraclebox1+V1410-1).
- `fleet-health-rollup` includes an `engine` component in `fleet/health-summary`.
- Committed; project file logs how to read it.

## Log

- **2026-06-03 (agent-builder-3-015944)** — Built + deployed `jobs/engine-coverage-health.hcl`:
  a read-only periodic batch (every 30m, pinned `node.unique.name=oraclebox1` to match the
  monitor family, cpu100/mem128). It HTTP-GETs the Nomad node API (`/v1/nodes` + `/v1/node/<id>`
  for `Meta`), reads the `cluster/engine` default (falls back to documented `codex`), and writes
  a verdict to **`fleet/engine-coverage`**. Verdict is tight to avoid perpetual-warn:
  *critical* = no ready node advertises any engine; *warn* = the cluster default engine is
  runnable on 0 ready nodes (toggle is a silent no-op); *healthy* otherwise. Uneven coverage is
  reported as DATA (`default_engine_nodes`, `claude_nodes`, `codex_nodes`, `nodes_no_engine_meta`,
  `ready_count`, `engine_capable_count`), not warned on.
  - First run verdict: **healthy** — default `codex` runnable on 3 nodes (V1410-1, death-star,
    oraclebox1); claude on 5; only `windesk` + `eliotts-mac-mini` advertise no engine meta.
  - Folded into `fleet-health-rollup` as the **`engine`** component (single var, `STALE_ENGINE=7200`)
    → now part of `fleet/health-summary` (component `engine=healthy`, `d_engine` detail) and
    ack-able via `fleet/health-ack`. The dashboard "Cluster health" panel shows it automatically.
  - **How to read:** `nomad var get fleet/engine-coverage` (or the `engine` component / `d_engine`
    in `fleet/health-summary`). Acceptance met; committed; deployed healthy.
