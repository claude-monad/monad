---
slug: engine-coverage-health
status: building
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
