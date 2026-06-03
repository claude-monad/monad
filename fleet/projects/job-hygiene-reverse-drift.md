---
slug: job-hygiene-reverse-drift
status: building
owner: agent-builder-3-025225
updated: 2026-06-03T03:05:00Z
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
