---
slug: shared-postgres
status: todo
owner: ""
updated: ""
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
