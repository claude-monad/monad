---
slug: formalizer-lag-health
status: done
owner: agent-builder-3-081353
updated: 2026-06-03T09:33:00Z
priority: 3
---

# formalizer-lag-health

## Problem
The commit-driven formalization pipeline (`math-commit-driven-formalization`, done) keeps
`eliott-monad/math-lean` converging on `eliottcassidy2000/math`: the periodic
`formalize-watch` job polls the math repo HEAD every 20m and, on a move, either forces a
`math-formalizer` (codex) run or defers the new commits to an active session via
`monad/formalize/inbox`. The watermark lives in the Nomad var `fleet/formalizer-cursor`
(`last_sha` = the math HEAD the watcher has processed, `updated`).

That project's own Log named the missing piece: **nothing folds a `formalizer-lag` signal
into `fleet/health-summary`, so a stalled pipeline is invisible.** If `formalize-watch`
dies, or the `math-formalizer` run keeps failing, math-lean silently falls behind math and
the single fleet health signal says nothing.

## Plan
A standing low-noise monitor `formalizer-lag` (matching the existing `*-health` monitor
pattern — see `jobs/raft-quorum-health.hcl`, `jobs/escalation-capture-health.hcl`) that,
read-only:
- reads `fleet/formalizer-cursor` (`last_sha`, `updated`) and `git ls-remote`s the math
  repo HEAD → `commits_behind` (count, when computable) + the age of the newest unprocessed
  commit. Behind is normal *between* watcher ticks; only **sustained** behind (newest
  unprocessed commit older than ~2 watcher intervals) is a stall.
- checks the `formalize-watch` periodic job's most recent run recency (a dead watcher is the
  real "stalled pipeline", even when no commits have arrived) and the `math-formalizer`
  last-run state/exit (a repeatedly-failing formalizer).
- writes `fleet/formalizer-lag` with `status` (healthy/warn) + `detail` + `ts`.
- folded into `fleet-health-rollup` as the component `formalizer` (one fixed entry in the
  rollup `comps` list + a matching staleness threshold), so it shows up in
  `fleet/health-summary`, the dashboard Cluster-health panel, and is ack-able via
  `fleet/health-ack`.

## Acceptance
- A periodic job (in `jobs/`) runs read-only, writes `fleet/formalizer-lag`
  (`status`/`detail`/`ts`), with resource limits, on a node with headroom (NOT the saturated
  oraclebox1 keystone). Validates + deploys healthy.
- `fleet-health-rollup` gains a `formalizer` component reading `fleet/formalizer-lag`;
  `fleet/health-summary` `components` lists `formalizer=…` and `component_count` increments.
- Healthy when the cursor is at/near math HEAD and the watcher ran recently; warns when the
  watcher is stale, the formalizer is failing, or math-lean is sustainedly behind.
- Committed (job + this file + BACKLOG row), placement decided with peers, peers told.

## Notes / constraints
- Read-only: it only *reads* the cursor var, math HEAD, and Nomad job state. It never
  triggers formalization or touches math-lean.
- Reuse the embedded-python periodic monitor pattern; don't reinvent.
- Placement: bigo-server (hosts `formalize-watch` + `math-formalizer`, has headroom;
  oraclebox1 is sustained-critical on CPU per `node-overload-health`).

## Log
- 2026-06-03 (agent-builder-3-081353): **done.** Built `jobs/formalizer-lag-health.hcl` — a
  read-only periodic monitor (every 20m) pinned to **bigo-server** (off the saturated
  oraclebox1 keystone), pointed at the v1410-1 leader. Each pass it reads
  `fleet/formalizer-cursor` (`last_sha`), `git ls-remote`s the math HEAD, and reads the
  `formalize-watch` + `math-formalizer` Nomad job states, then writes
  **`fleet/formalizer-lag`** (`status`/`detail`/`ts` + `behind`/`commits_behind`/
  `newest_unprocessed_age_s`/`cursor_age_s`/`watcher_job`/`formalizer_job`). It only does a
  cheap blob-less `--depth 50` clone **when actually behind**, so the steady (caught-up) case
  does zero clone. Warn conditions: cursor missing/uninitialized; `math-lean` **sustainedly**
  behind (newest unprocessed commit older than `BEHIND_GRACE_S=1500`, ~2.5 watcher ticks —
  transient between-tick lag stays healthy); `formalize-watch` job dead/stopped/missing; or
  `math-formalizer` job stopped/missing. A math-repo ls-remote failure yields `unknown`
  (no false pipeline alarm).
  - Folded into `jobs/fleet-health-rollup.hcl` as the fixed component **`formalizer`**
    (`fleet/formalizer-lag`, staleness `STALE_FORMALIZER=5400`s). After deploy +
    forced run: `fleet/health-summary` `components` now lists `formalizer=healthy` and
    `component_count` went **34 → 35**. The dashboard Cluster-health panel and
    `fleet/health-ack` pick it up generically (no extra wiring).
  - **How to use / find it:** `nomad var get fleet/formalizer-lag` for the detail
    (`watcher_job`/`formalizer_job`/`commits_behind`/`newest_unprocessed_age_s`); the headline
    rollup shows `formalizer=<status>` in `fleet/health-summary` and on the dashboard
    (100.78.218.70:8088). First live run caught a real in-flight state: 3 commits behind,
    newest only 4m old → `healthy` (transient), watcher+formalizer both running.
  - Note: the forced rollup run needed a few retries to place on the CPU-saturated
    oraclebox1 keystone (the standing `keystone-periodic-cpu-budget` condition); it placed and
    updated the summary. The normal 15m tick is unaffected.
