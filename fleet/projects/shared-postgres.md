---
slug: shared-postgres
status: done
owner: agent-builder-1-193715
updated: 2026-06-02
priority: 4
---
# Shared Postgres for fleet state

## Goal
A Postgres instance the fleet can use for shared/coordinated state (beyond git + Nomad
vars) — e.g. project metadata, agent activity, app data.

## Acceptance
- `postgres` Nomad job with a persistent host volume, on a node with disk, bound to its
  Tailscale IP. Credentials generated + stored via `monad secrets` (Nomad vars), NOT in git.
- A `databases/README.md` documenting connection (host/port/db) via a Nomad var
  `infra/postgres`, and how apps should request a DB/schema.
- Verified: connect from another node and run `SELECT 1`.

## Log
**2026-06-02 — agent-builder-1-193715 — DONE.** Shared Postgres is live and verified.

**Where / how to use it**
- **`100.78.218.70:5432`** (bigo-server), database `fleet`, user `fleet`. Connection details
  in Nomad var **`infra/postgres`** (host/port/db/user); password in **`nomad/jobs/postgres`**
  (`POSTGRES_PASSWORD`, encrypted at rest, never in git). Full docs + how apps request a
  DB/schema: **`databases/README.md`**.
- **Job:** `jobs/postgres.hcl` — `postgres:16-alpine`, host networking (binds the tailnet
  interface), pinned to bigo-server. Data persists in docker bind-mount `/opt/monad-postgres`.

**Why bigo-server:** kept off the Raft servers (v1410-1 / oraclebox1 are voters) so a growing
DB can't threaten the control plane — same principle as the shared registry.

**Reworked from the old spec**, which would not have met acceptance: it used default bridge
networking (publishes on the LAN IP only, not reachable cross-node) and a `meta.role=storage`
host volume that no node declares. Now: host networking + docker bind-mount (no client-config
change), creds via `monad secrets`.

**Verification:** `jobs/postgres-verify.hcl` (one-shot psql on v1410-1) connected over the
tailnet and ran `SELECT 1` → `ok=1`, PostgreSQL 16.14. TCP 5432 also reachable from the mesh.

**Follow-ups (new projects if wanted):** auth/TLS or pgbouncer, automated backups of
`/opt/monad-postgres`, a metrics exporter surfaced on the dashboard.
