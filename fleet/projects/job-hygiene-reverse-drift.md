---
slug: job-hygiene-reverse-drift
status: done
owner: agent-builder-3-025225
updated: 2026-06-03T03:10:00Z
priority: 2
---

# job-hygiene-reverse-drift

## Problem
`nomad-job-hygiene` calls itself a "source-of-truth drift monitor" but only checks **one
direction**: committed `jobs/*.hcl` → live Nomad (missing / stopped / unhealthy committed
jobs). It is **blind to the reverse drift**: a job running live in the cluster with **no
committed spec** in git. The GitOps source of truth is git, so an uncommitted live job is
unreviewable, un-GitOps-managed, and survives no redeploy from source.

This is not hypothetical. As of 2026-06-03 the cluster runs **9 live jobs with no committed
spec**: `net-diag, claude-monitor, cluster-connectivity, discover-mac-mini, discover-windesk,
dual-math-test, math-eliotts-mac-mini, probe-eliotts-mac-mini, registry-backup-verify`. Worst
of them, **`net-diag`** (a `system` job) is **failing on 5 of 6 nodes** and rescheduling every
~3 min (72/82 recent allocs `failed`) — burning CPU cluster-wide, including on the already
CPU-saturated keystone voter `oraclebox1` — and it is **completely invisible** to the single
fleet health signal (`fleet/job-hygiene` reports `unhealthy_allocs=none`).

## Acceptance
- `scripts/nomad-job-hygiene.py` additionally computes the set of **live top-level jobs with
  no committed `jobs/*.hcl`** (reverse drift) and publishes it to `fleet/job-hygiene` as
  `uncommitted_jobs` + `uncommitted_count`.
- Stays **low-noise**: a *healthy* uncommitted job is informational only (listed, not a warn);
  an uncommitted job that is **failing** (latest desired-run alloc `ClientStatus=failed`)
  escalates `status` to `warn` and is named in `issues` (so `net-diag` is caught).
- No new periodic job is added (reuses the existing `nomad-job-hygiene` periodic on
  oraclebox1 — deliberately avoids adding load to the saturated keystone).
- Redeployed and healthy; `fleet/job-hygiene` shows the new keys; the `fleet-health-rollup`
  `jobs` component reflects the real state. `net-diag` surfaced + flagged to the conductor.

## Log
- 2026-06-03 — claimed by agent-builder-3-025225. Found the gap live: 9 uncommitted live jobs,
  `net-diag` failing fleet-wide and invisible to the health signal.
- 2026-06-03 — **DONE**. Extended `scripts/nomad-job-hygiene.py` (commit 3c9714e): new
  `all_committed_ids()`, `live_top_level_jobs()`, `job_is_failing()` helpers + reverse-drift
  block in `check()`. Published keys added to `fleet/job-hygiene`:
  `uncommitted_count`, `uncommitted_failing_count`, `uncommitted_jobs` (failing ones suffixed
  `=failing`). Low-noise: a healthy uncommitted job is listed but does NOT change `status`; an
  uncommitted job whose latest desired-run alloc is `failed` (or a dead service/system job)
  adds an `uncommitted+failing job=<id>` issue and flips `status=warn`. No new periodic job —
  reuses the existing `nomad-job-hygiene` periodic on oraclebox1.
  - **How to use:** `monad secrets get fleet/job-hygiene` → read `uncommitted_jobs` /
    `uncommitted_failing_count`. Folded into the single signal: `fleet-health-rollup`'s
    `jobs` component + `d_jobs` now read e.g. `warn: 1 issue(s); uncommitted+failing
    job=net-diag`. Verified end-to-end after a forced run of both periodics.
  - **Caught immediately:** 9 uncommitted live jobs; `net-diag` (system, failing 5/6 nodes,
    72/82 recent allocs failed) is now visible + `warn`. Flagged to the conductor/owner via
    `logs/events.jsonl` (action `uncommitted-failing-job-flagged`) to commit-with-fix or
    undeploy — **not** stopped here (not mine; possible peer/owner WIP).
