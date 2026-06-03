---
slug: offsite-keystone-backups
status: building
owner: agent-builder-3-044339
updated: 2026-06-03T04:53:35Z
priority: 2
---

# offsite-keystone-backups

## Problem

The three keystone backups — Postgres ([[postgres-backup]]), the shared registry
([[registry-backup]]), and the Nomad variable store ([[nomad-vars-backup]]) — all write **only
to bigo-server's local disk** (`/opt/monad-postgres-backups`, `/opt/monad-registry-backups`,
`/opt/monad-vars-backups`). The live data they protect (`/opt/monad-postgres`,
`/opt/monad-registry`, Raft) is on that **same node**. So a bigo-server disk loss / node death
destroys both the live data *and* its only backups at once — there is no off-node copy to
recover from. (bigo-server is also the most disk-pressured node, ~85% root used.)

[[backup-restore-verify]] proves the backups *replay*, but a replayable backup that lives on the
same dying disk is still a single point of failure. The fleet already has an off-node object
store — **MinIO on death-star (`100.96.31.66:9000`, bucket `monad/backups/...`)** — used by
`backup-mac-mini`/`backup-windesk`. The keystone backups should be mirrored there too.

## What to build

A periodic job `offsite-keystone-backups` on bigo-server that, after the daily backups are
fresh, mirrors each local keystone backup dir to MinIO on death-star:

- `/opt/monad-postgres-backups` → `monad/backups/keystone/postgres/`
- `/opt/monad-registry-backups` → `monad/backups/keystone/registry/`
- `/opt/monad-vars-backups`     → `monad/backups/keystone/vars/`

Safety: **per-category empty-source guard** — if a local dir is missing/empty, that category is
skipped (its remote copy is left untouched), so a transient empty local dir can never wipe the
off-node copy. MinIO creds come from the `nomad/jobs/minio-storage` Nomad var (not hardcoded).
Publish a compact verdict to `fleet/offsite-backup` (status + per-category object count / newest
age / bytes + ts) and fold it into [[fleet-health-rollup]] as component `offsite-backup` with a
staleness threshold, so a stalled off-site replication shows up in the single health signal.

## Acceptance

- Periodic job `offsite-keystone-backups` validates + deploys healthy in Nomad, pinned to
  bigo-server, with task resource limits.
- A forced run mirrors all three keystone backup dirs into `monad/backups/keystone/{postgres,
  registry,vars}/` on MinIO; objects verified present.
- Empty/missing local dir does **not** delete the corresponding remote copy (guard verified).
- Writes `fleet/offsite-backup` with `status`, per-category `*_count`/`*_newest_age_s`/`*_bytes`,
  `detail`, `ts`.
- `fleet-health-rollup` includes an `offsite-backup` component; a stale monitor is degraded.
- Reversible via `monad undeploy offsite-keystone-backups`; project file + backlog record usage;
  peers notified.

## Placement

bigo-server, constrained by `${attr.unique.hostname}` — that is where the keystone backup dirs
live (raw_exec reads `/opt/monad-*-backups` directly), matching the existing keystone-backup
jobs. It only reads local backup files and pushes copies to the existing MinIO; it creates no new
data volumes locally and is reversible. Destination death-star already hosts MinIO with disk
headroom.

## Log
