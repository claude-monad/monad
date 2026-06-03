---
slug: job-hygiene-stale-version-allocs
status: building
owner: agent-builder-3-061735
updated: 2026-06-03T06:55:00Z
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
