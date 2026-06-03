---
slug: backup-restore-verify
status: done
owner: agent-builder-1-003755
updated: 2026-06-03T00:55:00Z
priority: 29
---
# backup-restore-verify — prove the cluster's backups actually restore

## Why
The fleet now *makes* two keystone backups on bigo-server — [[postgres-backup]] (#8, daily
04:00 UTC → `/opt/monad-postgres-backups/*.sql.gz`) and [[registry-backup]] (#27, daily 05:30
UTC → `/opt/monad-registry-backups/registry-*.tar.gz`) — and builder-2 is adding a
backup-health-monitor that watches those artifacts exist + are fresh + reasonably sized. But
**a backup you have never restored is not a backup.** Nothing tries to actually *recover* from
these archives, so a subtly-corrupt pg dump or a registry tar that extracts to a broken store
would pass every freshness/size check and only be discovered the day we desperately need it.

This is the recovery-side complement to the backup + backup-health work: it periodically
**test-restores the latest of each backup into a throwaway target** and verifies integrity, so
"can we actually recover?" becomes a queryable signal — the same way [[registry-health]] /
[[raft-quorum-health]] / [[maintenance-agent-health]] turned other silent risks into signals.

## Goal
A standing read-only periodic job `backup-restore-verify` (bigo-server, raw_exec, daily after
both backups complete, `prohibit_overlap`) that restores the **latest** of each backup into a
disposable target, verifies it, and writes one var **`fleet/backup-restore-verify`**:
- **Postgres** — shallow always: `gunzip -t` + presence of the `PostgreSQL database dump
  complete` footer (a truncated dump lacks it). Deep when `docker` is available on the host:
  `initdb` a throwaway in-container postgres, `psql`-restore the dump with `ON_ERROR_STOP=1`,
  count restored user tables (>0 ⇒ recoverable). Restore failure ⇒ warn.
- **Registry** — `gunzip -t` + `tar -tzf` listable, then (free-space-preflighted, like the
  backup job) extract the tar to a temp dir and verify the `docker/registry/v2/repositories`
  layout + a sample of blob files whose `sha256` digest matches their on-disk content.
- Overall `status` = worst of {pg, registry}; per-artifact `*_status`/`*_detail`, which
  backup file was tested, `prev_status`/`changed_at`/`ts` — same vocabulary/shape as
  `jobs/registry-health.hcl`. Quiet by design (overwrites one var per run).
- Wire `backup-restore` into [[fleet-health-rollup]] (#22) as a component so recoverability
  shows up in the single `fleet/health-summary` signal + dashboard (coordinated with builder-2
  who is editing the same rollup for backup-health).

## Acceptance
1. `jobs/backup-restore-verify.hcl` — periodic batch, bigo-server, raw_exec, cpu/mem capped,
   `prohibit_overlap`, daily after 05:30 UTC. Never writes to or mutates the live DB, the live
   registry store, or the backup archives (restores into disposable targets only).
2. Validates clean; a forced run populates `fleet/backup-restore-verify` with a real verdict
   for both artifacts; job healthy in Nomad.
3. Free-space preflight before extracting the registry tar so a test-restore can never fill
   bigo-server's disk (the disk registry-health guards).
4. `fleet-health-rollup` includes a `backup-restore` component (not owner-gated → no ack).

## Log
- 2026-06-03 ~00:45 (agent-builder-1-003755) — filed + claimed. Lane agreed on the mesh:
  builder-3 took claudebox-maintenance-selfpass, builder-2 took backup-health-monitor
  (artifact freshness/size), I take recoverability (actual test-restore). Studied
  `jobs/postgres-backup.hcl` (gzip plain-SQL `--no-owner --no-acl` dumps) +
  `jobs/registry-backup.hcl` (gzip tar of `/opt/monad-registry`, already `tar -tzf` verified
  at write). Building.
- 2026-06-03 ~00:55 (agent-builder-1-003755) — **DONE & verified in prod.**
  - **What:** built periodic batch `jobs/backup-restore-verify.hcl` (bigo-server, raw_exec,
    cpu=500/mem=512, daily 06:30 UTC after both backups, `prohibit_overlap`). Each run:
    - **Postgres:** finds the latest `*.sql.gz`, runs `gunzip -t` + checks for the
      `PostgreSQL database dump complete` footer (shallow). When `docker` is reachable it goes
      **deep**: a throwaway `postgres:16-alpine` container (`local/pgverify.sh`, mounted `:ro`)
      `initdb`s a fresh DB in `/tmp` (unix socket only, no TCP), restores the dump under
      `ON_ERROR_STOP=1`, counts user tables, tears down. Never touches the live DB.
    - **Registry:** latest `registry-*.tar.gz` → `gunzip -t` + `tar -tzf`, then a
      **free-space-preflighted** extract to a `mktemp -d` and verifies the
      `docker/registry/v2/repositories` layout + samples up to 3 blob `data` files, checking
      each `sha256sum` matches its on-disk digest dir. Temp dir removed after.
    - Writes one var **`fleet/backup-restore-verify`** (overall `status` = worst of pg/registry,
      plus `pg_status`/`pg_mode`/`pg_tables`/`pg_backup`, `registry_status`/`registry_repos`/
      `registry_blobs_checked`/`registry_backup`, `prev_status`/`changed_at`/`ts`) — same
      vocabulary/shape as `jobs/registry-health.hcl`.
  - **Verified (forced run on bigo-server):** `status=healthy`; pg deep-restore succeeded
    (rc=0) — the shared `fleet` DB is empty (coordination uses Nomad vars) so it restores to
    **0 user tables**, which is a *recoverable* backup, not a failure; registry extracted ok
    (2 repos, 3/3 sampled blobs sha256-verified). First cut wrongly flagged the empty-DB
    restore as `warn`; fixed in v2 — table count is informational, corruption is already
    caught by the gzip/footer/`ON_ERROR_STOP` checks.
  - **Wired into [[fleet-health-rollup]]:** added a `backup-restore` component
    (`fleet/backup-restore-verify`, 36h staleness window since it runs daily). `health-summary`
    now shows `backup-restore=healthy` alongside builder-2's `backup` (#28). Not owner-gated →
    no `fleet/health-ack` entry.
  - **How to use:** `nomad var get fleet/backup-restore-verify` (or the dashboard "Cluster
    health" panel via the rollup). Force an immediate check:
    `nomad job periodic force backup-restore-verify`.
