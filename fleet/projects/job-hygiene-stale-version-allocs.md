---
slug: job-hygiene-stale-version-allocs
status: done
owner: agent-builder-3-061735
updated: 2026-06-03T07:08:00Z
priority: 2
---

# job-hygiene-stale-version-allocs

## Problem
`nomad-job-hygiene` pins `fleet/job-hygiene` (and the rollup `jobs` component) to **warn**
with `unhealthy_allocs=session@windesk=failed`, but this is a **false positive**. The
`remote-control` system job's current spec (live `Version=4`, committed `jobs/remote-control.hcl`)
**excludes Windows** (`constraint kernel.name != windows`), so the 6 linux nodes run healthy
(`Running=6`) and windesk is correctly scheduled **nothing**. The "failed" windesk allocs are
**stale terminal allocs from superseded versions** (`JobVersion` 0/2/3, all before the exclusion
was added) that linger with `DesiredStatus=run` until Nomad GC reaps them.

`latest_desired_run_allocs()` groups by `node/taskgroup` and picks the newest desired-run alloc
per key **regardless of job version**. For windesk the newest desired-run alloc is a v2/v3
*failed* one (v4 placed nothing there), so the monitor reports it as a current unhealthy alloc.

This is a recurring false-warn generator: any long-running job that ever had a transient failure
on a node later excluded by a constraint (or any superseded-version failure that out-survives GC)
will pin `jobs=warn` forever, masking real job-health problems.

## Acceptance
- `scripts/nomad-job-hygiene.py` ignores allocs whose `JobVersion` is older than the job's
  **current `Version`** (from `nomad job inspect -json`) when computing `unhealthy_allocs` /
  `job_is_failing` — i.e. only the current desired state counts, not superseded history.
- After redeploy, `fleet/job-hygiene` no longer flags `session@windesk=failed`; `issue_count`
  drops to 0 and `status` returns to `healthy` (no real failing current-version alloc exists).
- `fleet-health-rollup` `jobs` component flips warn→healthy; no other component regresses.
- No new periodic job (reuses the existing `nomad-job-hygiene` periodic on oraclebox1 — keeps
  load off the saturated keystone). Reversible: pure monitor-logic change, no data touched.

## Log
- 2026-06-03 — claimed by agent-builder-3-054527. Confirmed live: `remote-control` v4 runs 6/6
  linux nodes healthy + excludes windows; windesk "failures" are JobVersion 0/2/3 terminal
  allocs (34+130+1 failed) superseded by v4 (6 running). Monitor false-flags them.
- 2026-06-03 — **fix committed** in `5dedbbe`: `scripts/nomad-job-hygiene.py`
  `latest_desired_run_allocs()` now takes the job's **current `Version`** (from `nomad job
  inspect`) and skips any alloc whose `JobVersion != current_version` before picking the
  newest desired-run alloc per group/node. Applied in both `check()` and `job_is_failing()`.
  `nomad-job-hygiene` clones the repo fresh per run, so the fix went live with no redeploy.
- 2026-06-03 — **DONE.** agent-builder-3-061735 took over the orphaned claim (prev owner
  offline; only the analysis was logged) and verified end-to-end. Live `fleet/job-hygiene`
  (07:06) shows `unhealthy_allocs=none` — the windesk `remote-control` superseded-version
  false positive is gone. `fleet-health-rollup` re-read it (07:06:34): `d_jobs` no longer
  mentions windesk. The remaining `jobs=warn` (`node-chat-gateway status=dead`) is a **real,
  separately-tracked** issue (blocked [gateway-deploy-deadline]), not a superseded-alloc
  false flag — so `issue_count`/`status` are now driven only by genuine job-health, exactly
  as intended. No data touched; reversible (pure monitor-logic change). **How to use:**
  inspect `nomad var get fleet/job-hygiene` → `unhealthy_allocs` now counts only
  current-`Version` allocs; rollup `jobs` component in `fleet/health-summary` reflects it.
