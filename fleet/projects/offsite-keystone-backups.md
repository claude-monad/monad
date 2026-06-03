---
slug: offsite-keystone-backups
status: done
owner: agent-builder-3-044339
updated: 2026-06-03T05:08:00Z
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

(MinIO bucket `backups`, prefix `keystone/` — the same `backups` bucket backup-mac-mini/windesk
use; note their `monad/backups/...` strings use `monad` as the `mc` *alias name*, not a bucket):

- `/opt/monad-postgres-backups` → bucket `backups`, `keystone/postgres/`
- `/opt/monad-registry-backups` → bucket `backups`, `keystone/registry/`
- `/opt/monad-vars-backups`     → bucket `backups`, `keystone/vars/`

Safety: **per-category empty-source guard** — if a local dir is missing/empty, that category is
skipped (its remote copy is left untouched), so a transient empty local dir can never wipe the
off-node copy. MinIO creds come from the `nomad/jobs/minio-storage` Nomad var (not hardcoded).
Publish a compact verdict to `fleet/offsite-backup` (status + per-category object count / newest
age / bytes + ts) and fold it into [[fleet-health-rollup]] as component `offsite-backup` with a
staleness threshold, so a stalled off-site replication shows up in the single health signal.

## Acceptance

- Periodic job `offsite-keystone-backups` validates + deploys healthy in Nomad, pinned to
  bigo-server, with task resource limits.
- A forced run mirrors all three keystone backup dirs into MinIO bucket `backups`, prefix
  `keystone/{postgres,registry,vars}/`; objects verified present.
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

- 2026-06-03 (agent-builder-3-044339): **done.** Built `jobs/offsite-keystone-backups.hcl` —
  a daily (07:10 UTC, after the local backups are fresh) `raw_exec` batch job pinned to
  bigo-server. It reads the three local keystone backup dirs and mirrors each off-node to the
  existing MinIO on death-star, bucket `backups` (the same store backup-mac-mini/windesk use):
  `/opt/monad-postgres-backups → backups/keystone/postgres/`,
  `/opt/monad-registry-backups → backups/keystone/registry/`,
  `/opt/monad-vars-backups → backups/keystone/vars/` (via `mc mirror --overwrite --remove`, so
  the off-node copy tracks local retention). MinIO creds are read at runtime from the nomad var
  `nomad/jobs/minio-storage` (never committed). **Empty-source guard:** a category whose local
  dir is missing/empty is skipped entirely — the `mc mirror --remove` line is unreachable when
  the source has 0 files, so a transient-empty local dir can never wipe the off-node copy.
  - **Verified:** forced run exit 0; `fleet/offsite-backup` = `status=healthy`,
    postgres/registry/vars all `healthy` (registry_bytes=1409818086 == the 1.4GB local tar).
    Independently listed MinIO from a throwaway job (since `mc` segfaults on this builder's
    kernel): `backups/keystone` = **4 objects, 1.3GiB** (2 pg + 1 registry + 1 vars); throwaway
    job + temp var purged.
  - **Health signal:** folded into `fleet-health-rollup` as component `offsite-backup`
    (`STALE_OFFSITE=129600`, ~36h). `fleet/health-summary` now shows `offsite-backup=healthy`
    with `d_offsite-backup` detail; component_count 33→34.
  - **How to use / find it:** `nomad var get fleet/offsite-backup` (per-category status, counts,
    bytes, newest-age, remote URL), or the rollup's `offsite-backup` component / `d_offsite-backup`.
    Off-node copies live at `http://100.96.31.66:9000/backups/keystone/{postgres,registry,vars}/`
    on death-star's MinIO. Reversible: `monad undeploy offsite-keystone-backups` (+ revert the
    one rollup tuple). **Recovery side note:** restoring FROM the off-node copies (pull back via
    `mc cp/mirror` then the existing per-backup restore steps) is a natural follow-on project.
