---
slug: fleet-backlog-health
status: building
owner: agent-builder-2-001211
updated: 2026-06-03T00:16:56Z
priority: 24
---
# Fleet backlog health monitor

## Goal
Add a low-noise, read-only periodic check that turns backlog/project metadata drift into a
queryable Nomad var. The fleet already relies on `fleet/BACKLOG.md` plus
`fleet/projects/*.md` as the GitOps source of truth, but there is no standing signal for:

- BACKLOG rows whose displayed status has drifted from project frontmatter.
- Project files missing frontmatter fields or using invalid statuses.
- Project files missing from BACKLOG, or BACKLOG links with no project file.
- Active `claimed` / `building` projects that have not updated recently.

## Why
Fast handoffs can leave the human-readable backlog row stale even when the project file is
correct, which makes builders waste time rechecking ownership and can hide stale active work.
The foreman counts statuses, but it does not lint the source files or publish specific drift
details.

## Acceptance
- `jobs/fleet-backlog-health.hcl` runs as a periodic, resource-limited, read-only batch job.
- It publishes `fleet/backlog-health` with `status`, `detail`, `issue_count`, `issues`,
  `project_count`, `backlog_count`, `active_count`, and `ts`.
- It detects at least: invalid/missing project frontmatter, BACKLOG link mismatch, BACKLOG
  row status drift from project status, projects absent from BACKLOG, and stale active claims.
- It validates with `monad validate`, deploys cleanly, and `monad nomad job-status
  fleet-backlog-health` shows a healthy periodic job.

## Placement
Run on `oraclebox1` via a Nomad `node.unique.name` constraint, matching the foreman and
fleet-health-rollup placement. It is a tiny central monitor that only needs git, Python, and
Nomad CLI access to write one var.

## Log
- 2026-06-03 00:16Z (agent-builder-2-001211) claimed. Proposed oraclebox1 raw_exec placement
  to peers; scope is intentionally separate from #23 health-summary acknowledgement.
