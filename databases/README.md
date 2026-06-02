# Shared Postgres for fleet state

A single Postgres instance the fleet can use for shared/coordinated state beyond git and
Nomad variables — project metadata, agent activity, app data, etc.

## Connection

| field | value | source |
|-------|-------|--------|
| host | `100.78.218.70` (bigo-server, tailnet) | Nomad var `infra/postgres` (`host`) |
| port | `5432` | `infra/postgres` (`port`) |
| database | `fleet` | `infra/postgres` (`db`) |
| user | `fleet` | `infra/postgres` (`user`) |
| password | *(secret)* | Nomad var `nomad/jobs/postgres` (`POSTGRES_PASSWORD`) |

```
postgresql://fleet:<password>@100.78.218.70:5432/fleet
```

- Non-secret connection details: `monad secrets get infra/postgres`
- Password (encrypted at rest, never in git): `monad secrets get nomad/jobs/postgres`
- **Job:** `jobs/postgres.hcl` — `postgres:16-alpine`, host networking, pinned to bigo-server.
  Data persists in the docker bind-mount `/opt/monad-postgres` on bigo-server.

## How a job should consume the credentials

Pull them from the Nomad variable in your job's `template` block (don't hardcode):

```hcl
template {
  data        = <<-EOT
{{ with nomadVar "nomad/jobs/postgres" }}
PGHOST=100.78.218.70
PGPORT=5432
PGUSER={{ .POSTGRES_USER }}
PGPASSWORD={{ .POSTGRES_PASSWORD }}
PGDATABASE={{ .POSTGRES_DB }}
{{ end }}
EOT
  destination = "secrets/pg.env"
  env         = true
}
```

`jobs/postgres-verify.hcl` is a working example (runs `SELECT 1` from another node).

## How apps should request a database / schema

The default `fleet` database is shared. To avoid stepping on each other:

- **Prefer a dedicated schema** inside `fleet` per app/agent, named after the app:
  `CREATE SCHEMA IF NOT EXISTS <app>;` then set `search_path` to it. This needs no superuser
  and no new credentials.
- **A dedicated database** (e.g. for isolation or a heavier app) is also fine — create it as
  the `fleet` superuser:
  `CREATE DATABASE <app> OWNER fleet;` and document it here.
- **Register what you create** by appending a row to the table below so the fleet knows who
  owns which schema/db. Keep DDL idempotent (`IF NOT EXISTS`).

### Registry of databases / schemas

| name | kind | owner (agent/app) | purpose |
|------|------|-------------------|---------|
| `fleet` | database | shared | default shared DB |
| `public` | schema | shared | default schema — prefer a named schema for app data |

## Admin

```bash
# open a psql shell from a node (uses the stored creds)
nomad var get -out json nomad/jobs/postgres   # to read creds, then:
PGPASSWORD=… psql -h 100.78.218.70 -U fleet -d fleet
```
