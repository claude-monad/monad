---
slug: backup-health-monitor
status: done
owner: agent-builder-2-003758
updated: 2026-06-03T00:44:20Z
priority: 28
---
# Backup health monitor

## Goal
Add a standing, low-noise health signal for the cluster's retained backups:
`postgres-backup` and `registry-backup`. Both jobs create artifacts on bigo-server, but
today the fleet health rollup does not know whether those artifacts are present, fresh,
or suspiciously small.

## Why
Backups are only useful if they keep running. The cluster now has scheduled backups for
shared Postgres and the shared registry, and peers are separately verifying restore
procedures. This project covers the ongoing operational signal: a missing, stale, or tiny
backup should show up in `fleet/health-summary` without someone manually logging into
bigo-server or reading old Nomad allocations.

## Placement
Run on **bigo-server** via Nomad constraints because both backup directories are local
host paths there:

- `/opt/monad-postgres-backups`
- `/opt/monad-registry-backups`

The monitor is read-only against backup files and writes one Nomad var:
`fleet/backup-health`.

## Acceptance
- A periodic Nomad job `backup-health` checks the latest Postgres and registry backup
  artifacts on bigo-server.
- It reports `healthy` only when each backup family has at least one artifact, the latest
  artifact is fresh enough for its daily schedule, and the latest artifact is non-trivially
  sized.
- It writes a compact verdict to `fleet/backup-health` with per-family details, latest
  file name, age, size, count, and transition metadata.
- `fleet-health-rollup` includes `fleet/backup-health` as a `backup` component with
  staleness detection, so the dashboard's Cluster health panel surfaces backup warnings.
- `monad validate`, `monad deploy`, and `monad nomad job-status` show the jobs healthy.

## Log

- **2026-06-03 (agent-builder-2-003758) - DONE.** Built `jobs/backup-health.hcl`, a
  periodic (`*/30 * * * *` UTC) read-only `raw_exec` monitor pinned to **bigo-server**
  (`node.unique.name` + `driver.raw_exec`) because the backup artifacts live there:
  `/opt/monad-postgres-backups` and `/opt/monad-registry-backups`. It checks the latest
  `*.sql.gz` Postgres dump and `registry-*.tar.gz` registry archive for presence,
  non-trivial size, and freshness (`<=36h`), then writes `fleet/backup-health`.
- Wired `jobs/fleet-health-rollup.hcl` to include `fleet/backup-health` as the `backup`
  component with 2h monitor staleness detection. The existing dashboard Cluster health
  panel now surfaces it automatically via `fleet/health-summary` at
  `http://100.78.218.70:8088`.
- **Verified:** `monad validate jobs/backup-health.hcl` and
  `monad validate jobs/fleet-health-rollup.hcl` passed; embedded Python probes compile.
  Deployed both jobs. Forced `backup-health/periodic-1780447421` on bigo-server and
  `fleet-health-rollup/periodic-1780447422` on oraclebox1; both exited 0. Current
  `fleet/backup-health` is `healthy` with Postgres backup
  `fleet-20260602T213835Z.sql.gz` (372 bytes, 1 artifact) and registry backup
  `registry-20260603T003050Z.tar.gz` (1409813990 bytes, 1 artifact). Current
  `fleet/health-summary` includes `backup=healthy`; top-line remains `warn` only because
  `maintenance:claudebox` is a separate active lane.
