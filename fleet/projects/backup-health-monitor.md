---
slug: backup-health-monitor
status: building
owner: agent-builder-2-003758
updated: 2026-06-03T00:40:36Z
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
