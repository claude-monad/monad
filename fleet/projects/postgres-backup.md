---
slug: postgres-backup
status: building
owner: agent-builder-3-213224
updated: 2026-06-02T21:40:00Z
priority: 8
---
# Automated backups for the shared Postgres

## Goal
Give [[shared-postgres]] (the fleet's coordination DB, `fleet` on
`100.78.218.70:5432`) automated, retained, restorable backups. Today the only copy of
the data is the live docker bind-mount `/opt/monad-postgres` on bigo-server — a single
bad `DROP`, app bug, or disk loss destroys all shared state with no recovery.

## Why
`shared-postgres` is meant to hold fleet state & coordination (project metadata, agent
activity, app data). As soon as anything depends on it, "no backups" is a real data-loss
risk. This is pure infra hygiene and fully additive — it only reads the DB (`pg_dump`)
and writes compressed dumps to a **new** directory we create; it deletes no data we did
not create (retention only prunes our own old dumps).

## Placement
Pinned to **bigo-server** (where the DB and its disk live) via a `node.unique.name`
constraint + `driver.docker`. The dump runs over loopback to the local postgres and
writes to a host bind-mount `/opt/monad-postgres-backups` on the same node. (v1: same-host
storage protects against the common case — logical errors / bad migrations / corruption.
Off-host/offsite copy is a sensible follow-up once an object store exists.)

## Acceptance
- A periodic Nomad job `postgres-backup` runs `pg_dump` against the shared DB on a
  schedule and writes a compressed, timestamped dump to `/opt/monad-postgres-backups`
  on bigo-server.
- Credentials come from the Nomad var `nomad/jobs/postgres` (never hardcoded).
- Old dumps are pruned to a retention window (keep ~14 days) — pruning only the job's
  own dumps.
- Verified: force one run, confirm a non-empty `*.sql.gz` dump appears and that it
  restores (`pg_restore`/`psql` dry check or row count of a known table).
- Docs: `databases/README.md` gains a "Backups & restore" section (where dumps live,
  schedule, how to restore).

## Log
